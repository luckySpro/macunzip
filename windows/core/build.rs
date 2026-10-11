fn main() {
    // unrar 在 Windows 上用到注册表、令牌和加密 API，unrar_sys 没有声明 advapi32
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        println!("cargo:rustc-link-lib=advapi32");
    }
}
