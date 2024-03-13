use std::{
    fs,
    io::{BufReader, Write},
    process::{Command, Stdio},
};

use anyhow::{bail, Result};
use indexmap::IndexMap;
use regex::{Regex, RegexBuilder};
use tracing::{debug, error, trace, warn};
use utf8_chars::BufReadCharsExt;

fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let general_regex = RegexBuilder::new(r"\]:* $").multi_line(true).build()?;
    let choices_regex =
        Regex::new(r"^\s*>?\s*(\d+)\.\s+.*?\(([A-Za-z0-9_]+)\)(?:\s+\(NEW\))?\s*$")?;
    let question_regex = Regex::new(r"(.*) \(([A-Za-z0-9_]+)\) \[(.*)\].*$")?;
    let choice_regex = Regex::new(r"choice\[(.*)\]: $")?;

    let file = fs::read_to_string("configs.toml")?;
    let mut configs: IndexMap<String, IndexMap<String, String>> = toml::from_str(&file)?;

    let mut linux_config = configs.swap_remove("linux").unwrap();

    let mut child = Command::new("make")
        .args([
            "-C",
            "sources/linux/linux-6.8",
            "ARCH=x86_64",
            "LLVM=/home/fede/projects/woven/sources/llvm/llvm-18.1.0-x86_64/bin/",
            "config",
        ])
        .stdout(Stdio::piped())
        .stdin(Stdio::piped())
        .spawn()?;

    let mut stdin = child.stdin.take().unwrap();
    let mut stdout = BufReader::new(child.stdout.take().unwrap());
    let mut stdout = stdout.chars();

    let mut line = String::new();
    let mut choices = IndexMap::new();

    let mut previous_was_question = false;

    while let Some(c) = stdout.next() {
        let c = c?;
        line.push(c);

        if c == '\n' {
            line.pop();

            if !previous_was_question {
                trace!("Received line: {line}");
                if line.contains("Restart config") {
                    let _ = child.wait();
                    bail!("Config got restarted. Something went wrong")
                }
            } else {
                previous_was_question = false;
                choices.clear()
            }

            if let Some(captures) = choices_regex.captures(&line) {
                choices.insert(captures[2].to_string(), captures[1].to_string());
            }

            line.clear()
        } else if !line.starts_with(">") && general_regex.is_match(&line) {
            previous_was_question = true;

            if let Some(captures) = question_regex.captures(&line) {
                trace!("Received question: {line}");

                let description = &captures[1];
                let name = &captures[2];
                let options = &captures[3];

                let mut answer = String::new();

                if let Some(name) = linux_config.swap_remove(name) {
                    answer = name;
                }

                if !answer.is_empty() {
                    debug!("Answering {name} with {answer}");
                    writeln!(stdin, "{answer}").expect("Fuck");
                } else {
                    debug!("Using default answer for {name}");
                    writeln!(stdin).expect("Dick");
                }
            } else if choice_regex.is_match(&line) {
                debug!("Received choice: {line}");

                let mut answer = String::new();

                for (name, choice) in &choices {
                    if let Some(name) = linux_config.swap_remove(name) {
                        if name == "y" {
                            answer.push_str(choice)
                        }
                    }
                }

                writeln!(stdin, "{answer}").expect("Fuck");
            } else {
                warn!("Couldn't understand: {line}");
            }
        }
    }

    for conf in linux_config.keys() {
        error!("{conf} wasn't used")
    }

    Ok(())
}
