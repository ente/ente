use std::{env, error::Error, fs, path::PathBuf};

fn main() -> Result<(), Box<dyn Error>> {
    println!("cargo:rerun-if-changed=native/chat.cpp");
    println!("cargo:rerun-if-env-changed=DEP_LLAMA_GGML_CMAKE_DIR");

    let cmake_dir = PathBuf::from(env::var("DEP_LLAMA_GGML_CMAKE_DIR")?);
    let output = cmake_dir
        .parent()
        .and_then(|path| path.parent())
        .ok_or("Invalid llama.cpp CMake directory")?;
    let cache_path = output.join("build/CMakeCache.txt");
    println!("cargo:rerun-if-changed={}", cache_path.display());
    let cache = fs::read_to_string(cache_path)?;
    let source = cache
        .lines()
        .find_map(|line| line.strip_prefix("CMAKE_HOME_DIRECTORY:INTERNAL="))
        .ok_or("llama.cpp source directory missing from CMake cache")?;
    let source = PathBuf::from(source);

    let mut build = cc::Build::new();
    build
        .cpp(true)
        .std("c++17")
        .file("native/chat.cpp")
        .include(source.join("common"))
        .include(source.join("include"))
        .include(source.join("ggml/include"))
        .include(source.join("vendor"))
        .cpp_link_stdlib(None);
    if build.get_compiler().is_like_msvc() {
        build.flag("/EHsc");
    }
    build.compile("ensu_chat");
    Ok(())
}
