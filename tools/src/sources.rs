use std::{
    fs::{self, File},
    io::{self, Read, Write},
    path::Path,
};

use anyhow::{bail, Result};
use bzip2::read::BzDecoder;
use camino::Utf8Path;
use flate2::read::GzDecoder;
use indicatif::ProgressBar;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256 as Sha256Hasher};
use tar::Archive;
use xz2::read::XzDecoder;

#[derive(Debug, Deserialize, Serialize)]
struct Config {
    sources: Vec<Source>,
}

#[derive(Debug, Deserialize, Serialize)]
struct Source {
    name: String,
    url: String,
    target: String,
    version: String,
    hash: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    let file = fs::read_to_string("sources.toml")?;
    let config: Config = toml::from_str(&file)?;

    let args: Vec<String> = std::env::args().collect();

    if let Some(source) = args.get(1) {
        print!(
            "{}",
            config
                .sources
                .iter()
                .find_map(|src| {
                    if &src.name == source {
                        Some(src.version.as_str())
                    } else {
                        None
                    }
                })
                .unwrap_or("unknown")
        );
        return Ok(());
    }

    fs::create_dir_all("sources/tar")?;

    let client = Client::new();

    for source in &config.sources {
        download_source(&client, source).await?;
        extract_source(source).await?;
    }

    println!("Sources OK");

    Ok(())
}

async fn download_source(client: &Client, source: &Source) -> Result<()> {
    let target_path: String = format!("sources/tar/{}", source.target);

    if Path::new(&target_path).exists() && check_hash(&target_path, &source.hash)? {
        return Ok(());
    }

    let mut target = File::create(target_path)?;

    println!("Downloading {}...", source.name);

    let mut res = client.get(&source.url).send().await?;
    let len = res.content_length().unwrap_or(0);

    let progress_bar = ProgressBar::new(len);

    while let Some(chunk) = res.chunk().await? {
        progress_bar.inc(chunk.len() as u64);
        target.write_all(&chunk)?;
    }

    progress_bar.finish();

    Ok(())
}

fn check_hash(path: &str, hash: &str) -> Result<bool> {
    let file = fs::read(path)?;
    let (hash_type, hash) = hash.split_once(':').unwrap_or(("blake3", hash));

    let computed_hash = match hash_type {
        "blake3" => blake3::hash(&file).to_hex().to_string(),
        "sha256" => base16ct::lower::encode_string(Sha256Hasher::digest(&file).as_slice()),
        _ => bail!("Unsupported hash"),
    };

    Ok(hash == computed_hash)
}

async fn extract_source(source: &Source) -> Result<()> {
    let target_path = format!("sources/tar/{}", source.target);
    let target_path = Utf8Path::new(&target_path);

    let archive_path = format!("sources/{}", source.name);
    let archive_path = Utf8Path::new(&archive_path);

    if archive_path.join(".ok").exists() {
        return Ok(());
    }

    if archive_path.exists() {
        fs::remove_dir_all(archive_path)?;
    }

    let target = File::open(target_path)?;

    match target_path.extension().unwrap() {
        "xz" => {
            unpack_archive(XzDecoder::new(target), &source.name)?;
        }
        "gz" => {
            unpack_archive(GzDecoder::new(target), &source.name)?;
        }
        "bz2" => {
            unpack_archive(BzDecoder::new(target), &source.name)?;
        }
        _ => bail!("Something went wrong extracting"),
    }

    Ok(())
}

fn unpack_archive<R: Read>(decoder: R, name: &str) -> Result<()> {
    println!("Unpacking {name}");

    let mut archive = Archive::new(decoder);

    archive.unpack(&format!("sources/{name}"))?;

    File::create(&format!("sources/{name}/.ok"))?;

    Ok(())
}
