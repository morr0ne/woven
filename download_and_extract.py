import httpx
import tarfile
from rich.progress import (
    Progress,
    BarColumn,
    DownloadColumn,
    TransferSpeedColumn,
    MofNCompleteColumn,
)
import os
import shutil

os.makedirs("sources/tar", exist_ok=True)


def download_file(url: str, file_name: str, pretty_name: str):
    with open(f"sources/tar/{file_name}", "wb") as file:
        with httpx.stream("GET", url, follow_redirects=True, timeout=None) as response:
            total = int(response.headers["Content-Length"])

            with Progress(
                "{task.description} [progress.percentage]{task.percentage:>3.0f}%",
                BarColumn(bar_width=None),
                DownloadColumn(),
                TransferSpeedColumn(),
            ) as progress:
                download_task = progress.add_task(
                    f"Downloading {pretty_name}", total=total
                )
                for chunk in response.iter_bytes():
                    file.write(chunk)
                    progress.update(
                        download_task, completed=response.num_bytes_downloaded
                    )


def extract_file(file_name: str, path: str, pretty_name: str):
    try:
        shutil.rmtree(path)
        print("Removing old extracted sources...")
    except:
        pass

    with tarfile.open(f"sources/tar/{file_name}") as tar:
        members = tar.getmembers()
        with Progress(
            "{task.description} [progress.percentage]{task.percentage:>3.0f}%",
            BarColumn(bar_width=None),
            MofNCompleteColumn(),
        ) as progress:
            extract_task = progress.add_task(
                f"Extracting {pretty_name}", total=len(members)
            )
            for member in members:
                tar.extract(member, path)
                progress.update(extract_task, advance=1)


def check_hash(path: str, hash: str) -> bool:
    return os.popen(f"b3sum --no-names {path}").read().strip() == hash


sources = [
    (
        "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.4.12.tar.xz",
        "linux.tar.xz",
        "sources/linux",
        "linux kernel sources",
        "8df063f93942fc139ef520b056f9ada0d9643d580f4b8a3495caf1eb0d1760a3",
    ),
    (
        "https://busybox.net/downloads/busybox-1.36.1.tar.bz2",
        "busybox.tar.bz2",
        "sources/busybox",
        "busybox sources",
        "dfdfc1b9aa41d5134e087d904c0a5f6958825f0e94db1d2cb5ea93088247c886",
    ),
    (
        "https://cdn.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.xz",
        "syslinux.tar.xz",
        "sources/syslinux",
        "syslinux sources",
        "ee03a3ec306d0131df30ed59ae0fa77987bb05bfe0a8169b59b4316c016cfdde",
    ),
]


for url, file_name, path, pretty_name, hash in sources:
    if os.path.isfile(f"sources/tar/{file_name}") and check_hash(
        f"sources/tar/{file_name}", hash
    ):
        print(f"File {file_name} exists already, skipping download")
    else:
        download_file(url, file_name, pretty_name)

    extract_file(file_name, path, pretty_name)
