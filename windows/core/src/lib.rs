//! MacUnZip Windows 版的压缩 / 解压核心，不依赖界面，可以单独测试。
//!
//! 解压先写到目标目录里的临时文件夹，完成后只有一个顶层项目就直接移出来，
//! 有多个就套一个以压缩包命名的文件夹，与 Mac 版行为一致。

use std::fs::{self, File};
use std::io::{self, BufReader, BufWriter, Read, Write};
use std::path::{Component, Path, PathBuf};

use serde::{Deserialize, Serialize};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("需要密码")]
    PasswordRequired,
    #[error("密码不正确")]
    WrongPassword,
    #[error("不支持的格式：{0}")]
    Unsupported(String),
    #[error("压缩包里的路径不安全：{0}")]
    UnsafePath(String),
    #[error("{0}")]
    Io(#[from] io::Error),
    #[error("{0}")]
    Other(String),
}

pub type Result<T> = std::result::Result<T, Error>;

/// 可以创建的格式。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Format {
    Zip,
    SevenZ,
    TarGz,
    TarZst,
}

impl Format {
    pub fn extension(self) -> &'static str {
        match self {
            Format::Zip => "zip",
            Format::SevenZ => "7z",
            Format::TarGz => "tar.gz",
            Format::TarZst => "tar.zst",
        }
    }
}

/// 压缩率，数值含义与 Mac 版一致：0 仅存储，1 最快，6 标准，9 最高。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Level {
    Store,
    Fast,
    Normal,
    Best,
}

impl Level {
    fn value(self) -> u32 {
        match self {
            Level::Store => 0,
            Level::Fast => 1,
            Level::Normal => 6,
            Level::Best => 9,
        }
    }
}

/// 识别出的压缩包类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Kind {
    Zip,
    SevenZ,
    Rar,
    Tar,
    TarGz,
    TarXz,
    TarBz2,
    TarZst,
    Gz,
    Xz,
    Bz2,
    Zst,
}

const SUFFIXES: &[(&str, Kind)] = &[
    (".tar.gz", Kind::TarGz),
    (".tgz", Kind::TarGz),
    (".tar.xz", Kind::TarXz),
    (".txz", Kind::TarXz),
    (".tar.bz2", Kind::TarBz2),
    (".tbz2", Kind::TarBz2),
    (".tbz", Kind::TarBz2),
    (".tar.zst", Kind::TarZst),
    (".tzst", Kind::TarZst),
    (".tar", Kind::Tar),
    (".zip", Kind::Zip),
    (".7z", Kind::SevenZ),
    (".rar", Kind::Rar),
    (".gz", Kind::Gz),
    (".xz", Kind::Xz),
    (".bz2", Kind::Bz2),
    (".zst", Kind::Zst),
];

fn kind_and_stem(path: &Path) -> Option<(Kind, String)> {
    let name = path.file_name()?.to_string_lossy().to_string();
    let lower = name.to_lowercase();
    SUFFIXES.iter().find(|(s, _)| lower.ends_with(s) && lower.len() > s.len()).map(|(s, k)| {
        (*k, name[..name.len() - s.len()].to_string())
    })
}

/// 是否是能解压的压缩包。
pub fn is_archive(path: &Path) -> bool {
    kind_and_stem(path).is_some()
}

/// 去掉压缩扩展名后的名字，例如 `资料.tar.gz` → `资料`。
pub fn base_name(path: &Path) -> String {
    kind_and_stem(path).map(|(_, s)| s).unwrap_or_else(|| {
        path.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default()
    })
}

/// 同名时依次尝试 `名字 2`、`名字 3`……
pub fn unique_path(path: &Path) -> PathBuf {
    if !path.exists() {
        return path.to_path_buf();
    }
    let parent = path.parent().unwrap_or(Path::new(""));
    let name = path.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
    // 扩展名可能是 tar.gz 这样的两段
    let (stem, ext) = match kind_and_stem(path) {
        Some((_, stem)) => {
            let ext = name[stem.len()..].to_string();
            (stem, ext)
        }
        None => match name.rfind('.') {
            Some(i) if i > 0 && !path.is_dir() => (name[..i].to_string(), name[i..].to_string()),
            _ => (name.clone(), String::new()),
        },
    };
    (2..)
        .map(|n| parent.join(format!("{stem} {n}{ext}")))
        .find(|p| !p.exists())
        .expect("unbounded")
}

/// 压缩包是否加密（需要先问密码）。
pub fn needs_password(archive: &Path) -> Result<bool> {
    match kind_and_stem(archive).map(|(k, _)| k) {
        Some(Kind::Zip) => {
            let mut zip = zip::ZipArchive::new(BufReader::new(File::open(archive)?)).map_err(other)?;
            for i in 0..zip.len() {
                match zip.by_index(i) {
                    Ok(f) if f.encrypted() => return Ok(true),
                    Ok(_) => {}
                    Err(zip::result::ZipError::UnsupportedArchive(m))
                        if m == zip::result::ZipError::PASSWORD_REQUIRED =>
                    {
                        return Ok(true)
                    }
                    Err(e) => return Err(other(e)),
                }
            }
            Ok(false)
        }
        Some(Kind::SevenZ) => {
            match sevenz_rust2::ArchiveReader::new(File::open(archive)?, sevenz_rust2::Password::empty()) {
                Ok(mut reader) => {
                    let mut encrypted = false;
                    let result = reader.for_each_entries(|_, r| {
                        let mut buf = [0u8; 1];
                        if let Err(e) = r.read(&mut buf) {
                            encrypted = is_7z_password_error(&e.to_string());
                        }
                        Ok(false)
                    });
                    if let Err(e) = result {
                        encrypted |= is_7z_password_error(&e.to_string());
                    }
                    Ok(encrypted)
                }
                Err(e) => Ok(is_7z_password_error(&e.to_string())),
            }
        }
        Some(Kind::Rar) => {
            let list = unrar::Archive::new(archive).open_for_listing().map_err(|e| {
                if format!("{e:?}").contains("MissingPassword") { Error::PasswordRequired } else { other(e) }
            });
            match list {
                Err(Error::PasswordRequired) => Ok(true),
                Err(e) => Err(e),
                Ok(list) => {
                    for entry in list {
                        if entry.map_err(other)?.is_encrypted() {
                            return Ok(true);
                        }
                    }
                    Ok(false)
                }
            }
        }
        Some(_) => Ok(false),
        None => Err(Error::Unsupported(archive.display().to_string())),
    }
}

fn is_7z_password_error(message: &str) -> bool {
    let m = message.to_lowercase();
    m.contains("password")
}

/// 解压 `archive` 到 `parent` 目录，返回结果路径（单个项目或包装文件夹）。
pub fn extract(archive: &Path, parent: &Path, password: Option<&str>) -> Result<PathBuf> {
    let (kind, stem) = kind_and_stem(archive).ok_or_else(|| Error::Unsupported(archive.display().to_string()))?;
    fs::create_dir_all(parent)?;
    let staging = parent.join(format!(".macunzip-{}", uuid::Uuid::new_v4()));
    fs::create_dir(&staging)?;
    let result = unpack(kind, &stem, archive, &staging, password).and_then(|_| settle(&staging, parent, &stem));
    let _ = fs::remove_dir_all(&staging);
    result
}

fn unpack(kind: Kind, stem: &str, archive: &Path, dest: &Path, password: Option<&str>) -> Result<()> {
    let open = || -> Result<BufReader<File>> { Ok(BufReader::new(File::open(archive)?)) };
    match kind {
        Kind::Zip => unzip(archive, dest, password),
        Kind::SevenZ => {
            let pw = password.map(sevenz_rust2::Password::from).unwrap_or_else(sevenz_rust2::Password::empty);
            sevenz_rust2::decompress_file_with_password(archive, dest, pw).map_err(|e| {
                let msg = e.to_string();
                if is_7z_password_error(&msg) {
                    if password.is_some() { Error::WrongPassword } else { Error::PasswordRequired }
                } else {
                    Error::Other(msg)
                }
            })
        }
        Kind::Rar => unrar_all(archive, dest, password),
        Kind::Tar => untar(open()?, dest),
        Kind::TarGz => untar(flate2::read::MultiGzDecoder::new(open()?), dest),
        Kind::TarXz => untar(xz2::read::XzDecoder::new_multi_decoder(open()?), dest),
        Kind::TarBz2 => untar(bzip2::read::MultiBzDecoder::new(open()?), dest),
        Kind::TarZst => untar(zstd::stream::read::Decoder::new(open()?)?, dest),
        Kind::Gz => single(flate2::read::MultiGzDecoder::new(open()?), dest, stem),
        Kind::Xz => single(xz2::read::XzDecoder::new_multi_decoder(open()?), dest, stem),
        Kind::Bz2 => single(bzip2::read::MultiBzDecoder::new(open()?), dest, stem),
        Kind::Zst => single(zstd::stream::read::Decoder::new(open()?)?, dest, stem),
    }
}

/// 把不可信的条目路径拼到 `dest` 下；含 `..`、绝对路径或盘符时拒绝。
pub fn safe_join(dest: &Path, entry: &str) -> Result<PathBuf> {
    let normalized = entry.replace('\\', "/");
    let mut out = dest.to_path_buf();
    for part in Path::new(&normalized).components() {
        match part {
            Component::Normal(p) => out.push(p),
            Component::CurDir => {}
            // 前导的 “/” 只是绝对写法，去掉后仍在目标目录内
            Component::RootDir => {}
            Component::ParentDir | Component::Prefix(_) => return Err(Error::UnsafePath(entry.to_string())),
        }
    }
    if normalized.contains(':') {
        return Err(Error::UnsafePath(entry.to_string()));
    }
    Ok(out)
}

fn unzip(archive: &Path, dest: &Path, password: Option<&str>) -> Result<()> {
    let mut zip = zip::ZipArchive::new(BufReader::new(File::open(archive)?)).map_err(other)?;
    for i in 0..zip.len() {
        let file = match password {
            Some(pw) => zip.by_index_decrypt(i, pw.as_bytes()),
            None => zip.by_index(i),
        };
        let mut file = file.map_err(|e| match e {
            zip::result::ZipError::InvalidPassword => Error::WrongPassword,
            zip::result::ZipError::UnsupportedArchive(m) if m == zip::result::ZipError::PASSWORD_REQUIRED => {
                Error::PasswordRequired
            }
            e => other(e),
        })?;
        let name = file.name().map_err(other)?.to_string();
        let out = safe_join(dest, &name)?;
        if file.is_dir() {
            fs::create_dir_all(&out)?;
            continue;
        }
        if let Some(p) = out.parent() {
            fs::create_dir_all(p)?;
        }
        let mut writer = BufWriter::new(File::create(&out)?);
        io::copy(&mut file, &mut writer).map_err(|e| {
            // ZipCrypto 的错误密码可能通过校验头，到 CRC 才发现
            if password.is_some() && e.kind() == io::ErrorKind::InvalidData { Error::WrongPassword } else { e.into() }
        })?;
        writer.flush()?;
    }
    Ok(())
}

fn unrar_all(archive: &Path, dest: &Path, password: Option<&str>) -> Result<()> {
    let opened = match password {
        Some(pw) => unrar::Archive::with_password(archive, pw).open_for_processing(),
        None => unrar::Archive::new(archive).open_for_processing(),
    };
    let map = |e: unrar::error::UnrarError| {
        let s = format!("{e:?}");
        if s.contains("MissingPassword") {
            Error::PasswordRequired
        } else if s.contains("BadPassword") || (password.is_some() && s.contains("BadData")) {
            Error::WrongPassword
        } else {
            other(e)
        }
    };
    let mut cursor = opened.map_err(map)?;
    while let Some(header) = cursor.read_header().map_err(map)? {
        let entry = header.entry();
        let out = safe_join(dest, &entry.filename.to_string_lossy())?;
        cursor = if entry.is_directory() {
            fs::create_dir_all(&out)?;
            header.skip().map_err(map)?
        } else {
            if let Some(p) = out.parent() {
                fs::create_dir_all(p)?;
            }
            header.extract_to(&out).map_err(map)?
        };
    }
    Ok(())
}

fn untar<R: Read>(reader: R, dest: &Path) -> Result<()> {
    let mut archive = tar::Archive::new(reader);
    for entry in archive.entries()? {
        let mut entry = entry?;
        let path = entry.path()?.to_string_lossy().to_string();
        let out = safe_join(dest, &path)?;
        match entry.header().entry_type() {
            tar::EntryType::Directory => fs::create_dir_all(&out)?,
            tar::EntryType::Regular | tar::EntryType::Continuous => {
                if let Some(p) = out.parent() {
                    fs::create_dir_all(p)?;
                }
                entry.unpack(&out)?;
            }
            // 链接和设备文件在 Windows 上没有安全的对应物，跳过
            _ => {}
        }
    }
    Ok(())
}

fn single<R: Read>(mut reader: R, dest: &Path, stem: &str) -> Result<()> {
    let mut out = BufWriter::new(File::create(dest.join(stem))?);
    io::copy(&mut reader, &mut out)?;
    out.flush()?;
    Ok(())
}

/// 把临时文件夹里的内容放到最终位置。
fn settle(staging: &Path, parent: &Path, stem: &str) -> Result<PathBuf> {
    let items: Vec<_> = fs::read_dir(staging)?.collect::<io::Result<_>>()?;
    if items.len() == 1 {
        let item = items[0].path();
        let target = unique_path(&parent.join(items[0].file_name()));
        fs::rename(&item, &target)?;
        Ok(target)
    } else {
        let target = unique_path(&parent.join(stem));
        fs::rename(staging, &target)?;
        fs::create_dir(staging)?; // 让调用方的清理照常进行
        Ok(target)
    }
}

/// 压缩选项。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompressOptions {
    pub format: Format,
    pub level: Level,
    /// 排除 Thumbs.db、desktop.ini、.DS_Store 等系统文件
    pub exclude_system_files: bool,
}

fn is_system_file(name: &str) -> bool {
    matches!(name.to_lowercase().as_str(), "thumbs.db" | "desktop.ini" | ".ds_store") || name.starts_with("._")
}

/// 收集要压缩的文件：(磁盘路径, 包内路径, 是否目录)。
fn collect(items: &[PathBuf], exclude: bool) -> Result<Vec<(PathBuf, String, bool)>> {
    let mut out = Vec::new();
    for item in items {
        let base = item.parent().unwrap_or(Path::new(""));
        for entry in walkdir::WalkDir::new(item).sort_by_file_name() {
            let entry = entry.map_err(|e| Error::Io(e.into()))?;
            let name = entry.file_name().to_string_lossy();
            if exclude && is_system_file(&name) {
                continue;
            }
            let rel = entry.path().strip_prefix(base).map_err(other)?;
            let rel = rel.components().map(|c| c.as_os_str().to_string_lossy()).collect::<Vec<_>>().join("/");
            out.push((entry.path().to_path_buf(), rel, entry.file_type().is_dir()));
        }
    }
    Ok(out)
}

/// 把 `items` 压缩到 `output`（调用方负责用 [`unique_path`] 避免覆盖）。
pub fn compress(items: &[PathBuf], output: &Path, options: &CompressOptions, password: Option<&str>) -> Result<()> {
    let files = collect(items, options.exclude_system_files)?;
    let tmp = output.with_file_name(format!(".macunzip-{}.part", uuid::Uuid::new_v4()));
    let result = match options.format {
        Format::Zip => write_zip(&files, &tmp, options.level, password),
        Format::SevenZ => write_7z(&files, &tmp, password),
        Format::TarGz => {
            if password.is_some() {
                return Err(Error::Unsupported("tar.gz 不支持密码".into()));
            }
            let enc = flate2::write::GzEncoder::new(File::create(&tmp)?, flate2::Compression::new(options.level.value()));
            write_tar(&files, enc).and_then(|enc| enc.finish().map(|_| ()).map_err(Into::into))
        }
        Format::TarZst => {
            if password.is_some() {
                return Err(Error::Unsupported("tar.zst 不支持密码".into()));
            }
            let level = match options.level { Level::Store => 1, Level::Fast => 1, Level::Normal => 3, Level::Best => 19 };
            let enc = zstd::stream::write::Encoder::new(File::create(&tmp)?, level)?;
            write_tar(&files, enc).and_then(|enc| enc.finish().map(|_| ()).map_err(Into::into))
        }
    };
    match result {
        Ok(()) => {
            fs::rename(&tmp, output)?;
            Ok(())
        }
        Err(e) => {
            let _ = fs::remove_file(&tmp);
            Err(e)
        }
    }
}

fn write_zip(files: &[(PathBuf, String, bool)], out: &Path, level: Level, password: Option<&str>) -> Result<()> {
    let mut zip = zip::ZipWriter::new(BufWriter::new(File::create(out)?));
    let method = if level == Level::Store { zip::CompressionMethod::Stored } else { zip::CompressionMethod::Deflated };
    let mut options = zip::write::SimpleFileOptions::default()
        .compression_method(method)
        .compression_level(if level == Level::Store { None } else { Some(level.value() as i64) })
        .large_file(true);
    if let Some(pw) = password {
        options = options.with_aes_encryption(zip::AesMode::Aes256, pw);
    }
    for (path, name, is_dir) in files {
        if *is_dir {
            zip.add_directory(format!("{name}/"), options).map_err(other)?;
        } else {
            zip.start_file(name, options).map_err(other)?;
            io::copy(&mut BufReader::new(File::open(path)?), &mut zip)?;
        }
    }
    zip.finish().map_err(other)?.flush()?;
    Ok(())
}

fn write_7z(files: &[(PathBuf, String, bool)], out: &Path, password: Option<&str>) -> Result<()> {
    let mut writer = sevenz_rust2::ArchiveWriter::new(File::create(out)?).map_err(other)?;
    if let Some(pw) = password {
        writer.set_content_methods(vec![
            sevenz_rust2::encoder_options::AesEncoderOptions::new(pw.into()).into(),
            sevenz_rust2::EncoderMethod::LZMA2.into(),
        ]);
    }
    for (path, name, is_dir) in files {
        let entry = sevenz_rust2::ArchiveEntry::from_path(path, name.clone());
        if *is_dir {
            writer.push_archive_entry::<File>(entry, None).map_err(other)?;
        } else {
            writer.push_archive_entry(entry, Some(File::open(path)?)).map_err(other)?;
        }
    }
    writer.finish()?;
    Ok(())
}

fn write_tar<W: Write>(files: &[(PathBuf, String, bool)], out: W) -> Result<W> {
    let mut tar = tar::Builder::new(out);
    for (path, name, is_dir) in files {
        if *is_dir {
            tar.append_dir(name, path)?;
        } else {
            tar.append_path_with_name(path, name)?;
        }
    }
    Ok(tar.into_inner()?)
}

fn other<E: std::fmt::Display>(e: E) -> Error {
    Error::Other(e.to_string())
}
