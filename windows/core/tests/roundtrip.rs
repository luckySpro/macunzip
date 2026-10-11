use std::fs;
use std::path::{Path, PathBuf};

use muz_core::*;

fn sample(dir: &Path) -> PathBuf {
    let root = dir.join("资料");
    fs::create_dir_all(root.join("子目录")).unwrap();
    fs::write(root.join("说明.txt"), "你好，MacUnZip").unwrap();
    fs::write(root.join("子目录/数据.bin"), vec![7u8; 100_000]).unwrap();
    fs::write(root.join("Thumbs.db"), "x").unwrap();
    root
}

fn opts(format: Format) -> CompressOptions {
    CompressOptions { format, level: Level::Normal, exclude_system_files: true }
}

fn roundtrip(format: Format, password: Option<&str>) {
    let tmp = tempfile::tempdir().unwrap();
    let src = sample(tmp.path());
    let archive = tmp.path().join(format!("资料.{}", format.extension()));
    compress(&[src.clone()], &archive, &opts(format), password).unwrap();
    assert_eq!(needs_password(&archive).unwrap(), password.is_some(), "{format:?}");

    let out = tmp.path().join("out");
    let result = extract(&archive, &out, password).unwrap();
    assert_eq!(result, out.join("资料"));
    assert_eq!(fs::read_to_string(result.join("说明.txt")).unwrap(), "你好，MacUnZip");
    assert_eq!(fs::read(result.join("子目录/数据.bin")).unwrap().len(), 100_000);
    assert!(!result.join("Thumbs.db").exists(), "系统文件应被排除");
    // 临时文件夹已清理
    assert_eq!(fs::read_dir(&out).unwrap().count(), 1);
}

#[test]
fn zip_roundtrip() { roundtrip(Format::Zip, None) }
#[test]
fn zip_password_roundtrip() { roundtrip(Format::Zip, Some("秘密123")) }
#[test]
fn sevenz_roundtrip() { roundtrip(Format::SevenZ, None) }
#[test]
fn sevenz_password_roundtrip() { roundtrip(Format::SevenZ, Some("秘密123")) }
#[test]
fn targz_roundtrip() { roundtrip(Format::TarGz, None) }
#[test]
fn tarzst_roundtrip() { roundtrip(Format::TarZst, None) }

#[test]
fn password_errors() {
    for format in [Format::Zip, Format::SevenZ] {
        let tmp = tempfile::tempdir().unwrap();
        let src = sample(tmp.path());
        let archive = tmp.path().join(format!("a.{}", format.extension()));
        compress(&[src], &archive, &opts(format), Some("right")).unwrap();
        let out = tmp.path().join("out");
        assert!(matches!(extract(&archive, &out, None), Err(Error::PasswordRequired)), "{format:?} 无密码");
        assert!(matches!(extract(&archive, &out, Some("wrong")), Err(Error::WrongPassword)), "{format:?} 错误密码");
        assert_eq!(fs::read_dir(&out).unwrap().count(), 0, "失败后不留临时文件");
    }
}

#[test]
fn multiple_items_are_wrapped() {
    let tmp = tempfile::tempdir().unwrap();
    let a = tmp.path().join("a.txt");
    let b = tmp.path().join("b.txt");
    fs::write(&a, "a").unwrap();
    fs::write(&b, "b").unwrap();
    let archive = tmp.path().join("两个文件.zip");
    compress(&[a, b], &archive, &opts(Format::Zip), None).unwrap();
    let out = tmp.path().join("out");
    let first = extract(&archive, &out, None).unwrap();
    assert_eq!(first, out.join("两个文件"));
    assert!(first.join("a.txt").exists() && first.join("b.txt").exists());
    let second = extract(&archive, &out, None).unwrap();
    assert_eq!(second, out.join("两个文件 2"));
}

#[test]
fn unique_names() {
    let tmp = tempfile::tempdir().unwrap();
    let p = tmp.path().join("资料.tar.gz");
    fs::write(&p, "").unwrap();
    assert_eq!(unique_path(&p), tmp.path().join("资料 2.tar.gz"));
    assert_eq!(base_name(&p), "资料");
}

#[test]
fn rejects_traversal() {
    let d = Path::new("dest");
    assert!(safe_join(d, "../evil").is_err());
    assert!(safe_join(d, "a/../../evil").is_err());
    assert!(safe_join(d, "..\\evil").is_err());
    assert!(safe_join(d, "C:/Windows/evil").is_err());
    assert_eq!(safe_join(d, "/abs/ok.txt").unwrap(), d.join("abs").join("ok.txt"));

    // 真实的恶意 zip
    let tmp = tempfile::tempdir().unwrap();
    let archive = tmp.path().join("evil.zip");
    {
        use std::io::Write;
        let mut zip = zip::ZipWriter::new(fs::File::create(&archive).unwrap());
        zip.start_file("../../evil.txt", zip::write::SimpleFileOptions::default()).unwrap();
        zip.write_all(b"x").unwrap();
        zip.finish().unwrap();
    }
    let out = tmp.path().join("deep/out");
    assert!(matches!(extract(&archive, &out, None), Err(Error::UnsafePath(_))));
    assert!(!tmp.path().join("evil.txt").exists());
}

#[test]
fn single_file_gz() {
    use std::io::Write;
    let tmp = tempfile::tempdir().unwrap();
    let gz = tmp.path().join("日志.txt.gz");
    let mut enc = flate2::write::GzEncoder::new(fs::File::create(&gz).unwrap(), flate2::Compression::default());
    enc.write_all(b"line").unwrap();
    enc.finish().unwrap();
    let out = extract(&gz, tmp.path(), None).unwrap();
    assert_eq!(out, tmp.path().join("日志.txt"));
    assert_eq!(fs::read_to_string(out).unwrap(), "line");
}
