# Copier Template for RPM Package Repositories

This repository is a template for creating RPM package repositories using [Copier](https://copier.readthedocs.io/en/stable/). It provides a standardized structure and tools for building and managing RPM packages at NSLS-II.

To initialize a new repository using this template, clone the template, and run the following:

```bash
pixi run copier copy . path/to/new/repository
```

and follow the prompts.

If you have `copier` installed, you can also pull the template directly from GitHub:

```bash
pixi run copier copy gh:NSLS2/rpm-repo-template path/to/new/repository
```
