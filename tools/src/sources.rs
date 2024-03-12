use std::{
    fs::{self, File},
    io::{self, Read, Write},
    path::Path,
};

use anyhow::{bail, Result};
use blake3::Hasher;
use bzip2::read::BzDecoder;
use camino::Utf8Path;
use flate2::read::GzDecoder;
use indexmap::IndexMap;
use indicatif::ProgressBar;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tar::Archive;
use xz2::read::XzDecoder;

#[derive(Debug, Deserialize, Serialize)]
struct Source {
    url: String,
    target: String,
    version: String,
    hash: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    let file = fs::read_to_string("sources.toml")?;
    let sources: IndexMap<String, Source> = toml::from_str(&file)?;

    fs::create_dir_all("sources/tar")?;

    let client = Client::new();

    for (name, source) in &sources {
        download_source(&client, name, source).await?;
        extract_source(name, source).await?;
    }

    println!("Sources OK");

    Ok(())
}

async fn download_source(client: &Client, name: &str, source: &Source) -> Result<()> {
    let target_path: String = format!("sources/tar/{}", source.target);

    if Path::new(&target_path).exists() && hash_path(&target_path)? == source.hash {
        return Ok(());
    }

    let mut target = File::create(target_path)?;

    println!("Downloading {name}...");

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

fn hash_path(path: &str) -> io::Result<String> {
    let mut hasher = Hasher::new();
    hasher.update_reader(File::open(path)?)?;
    let hash = hasher.finalize();

    Ok(hash.to_hex().to_string())
}

async fn extract_source(name: &str, source: &Source) -> Result<()> {
    let target_path = format!("sources/tar/{}", source.target);
    let target_path = Utf8Path::new(&target_path);

    let archive_path = format!("sources/{name}");
    let archive_path = Utf8Path::new(&archive_path);

    if archive_path.join(".ok").exists() {
        return Ok(());
    }

    fs::remove_dir_all(archive_path)?;

    let target = File::open(target_path)?;

    match target_path.extension().unwrap() {
        "xz" => {
            unpack_archive(XzDecoder::new(target), name)?;
        }
        "gz" => {
            unpack_archive(GzDecoder::new(target), name)?;
        }
        "bz2" => {
            unpack_archive(BzDecoder::new(target), name)?;
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
