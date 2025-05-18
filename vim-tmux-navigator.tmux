#!/usr/bin/env python3

import argparse
import logging
import re
import subprocess
import sys
from collections.abc import Sequence
from typing import cast

logger = logging.getLogger("vim-tmux-navigator")


def setup_logging(level_name: str) -> None:
    # fmt: off
    match level_name.upper():
        case "DEBUG":    level = logging.DEBUG
        case "INFO":     level = logging.INFO
        case "WARNING":  level = logging.WARNING
        case "ERROR":    level = logging.ERROR
        case "CRITICAL": level = logging.CRITICAL
        case _:          level = logging.INFO
    # fmt: on
    logging.basicConfig(
        format="%(asctime)s %(levelname)-5s %(name)s:%(lineno)d - %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
        level=level,
    )


def run(cmd: Sequence[str]) -> str:
    logger.debug(f"{' '.join(cmd)}")
    result = subprocess.check_output(cmd, text=True)
    return result.strip()


def tmux_version():
    try:
        output = run(["tmux", "-V"]).strip()
        match = re.search(r"(\d+)\.(\d+)([a-z]?)", output)
        logger.info(f"version: {output}")
        if not match:
            logger.error(f"Failed to parse tmux version: {output}")
            return None
        major, minor, patch_letter = match.groups()
        patch = ord(patch_letter) - 96 if patch_letter else 0
        return int(major), int(minor), patch
    except Exception as e:
        logger.error(f"Failed checking tmux version: {e}")
        return None


def version_check() -> None:
    logger.info("checking tmux version")
    version = tmux_version()
    if version is None or version < (3, 1, 0):
        logger.error(f"tmux 3.1 or higher is required. Found {version}")
        sys.exit(0)


def get_tmux_option(option: str, default_str: str) -> list[str]:
    try:
        value = run(["tmux", "show-option", "-gqv", option])
        if value and value.strip() == "":
            logger.debug(f"{option} has empty override")
            # empty value to clear keymap
            return [""]
    except subprocess.CalledProcessError:
        pass
    return default_str.split()


def bind_key_vim(key: str, cmd: str, note: str):
    logger.info(f"setting key '{key}'")
    is_vim = (
        "ps -o state= -o comm= -t '#{pane_tty}' | "
        + "grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?\\.?"
        + "(view|l?n?vim?x?|fzf)(diff)?(-wrapped)?$'"
    )
    # fmt: off
    _ = run(
        [
            "tmux", "bind-key", "-n",
            "-N", f"'{note}'",
            key,
            "if-shell", is_vim,
            f"send-keys '{key}'", cmd,
        ]
    )
    _ = run([
            "tmux", "bind-key", "-T", "copy-mode-vi",
            "-N", f"'{note}'",
            key,
            cmd
        ])
    # fmt: on


def main():
    parser = argparse.ArgumentParser(description="vim-tmux-navigator mappings")
    _ = parser.add_argument(
        "--log-level",
        choices=["debug", "info", "warning", "error", "critical"],
        type=str.lower,
        default="info",
        help="Set the logging level (case-insensitive)",
    )
    args = parser.parse_args()

    setup_logging(cast(str, args.log_level))

    version_check()

    # fmt: off
    directions = {
        "left":     {"key": "C-h",  "cmd": "select-pane -L"},
        "down":     {"key": "C-j",  "cmd": "select-pane -D"},
        "up":       {"key": "C-k",  "cmd": "select-pane -U"},
        "right":    {"key": "C-l",  "cmd": "select-pane -R"},
        "previous": {"key": "C-\\", "cmd": "select-pane -l"},
    }
    # fmt: on

    for direction, config in directions.items():
        keys = get_tmux_option(f"@vim_navigator_mapping_{direction}", config["key"])
        for key in keys:
            if not key.strip():
                logger.debug(f"skipping (key={key}, direction={direction})")
                continue
            bind_key_vim(key, config["cmd"], f"Move: {direction}")

    clear_screen = get_tmux_option("@vim_navigator_prefix_mapping_clear_screen", "C-l")
    for key in clear_screen:
        _ = subprocess.run(["tmux", "bind", key, "send-keys", "C-l"])


if __name__ == "__main__":
    main()
