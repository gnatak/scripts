# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

A collection of PowerShell scripts for Windows automation, currently focused on `winget` package synchronization across multiple PCs.

## Planned Scripts

### `wg_sync.ps1` (winget sync)
PowerShell script with three modes of operation:
- **Generate** — export currently installed winget packages to a file
- **Compare** — diff installed packages against a saved list
- **Install** — install packages from a saved list file
