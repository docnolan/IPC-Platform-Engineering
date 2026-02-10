# CI/CD Pipelines

This directory contains the Azure DevOps pipelines for building, scanning, signing, and validating the platform components.

## Documentation

> 📘 **See [Wiki: 08-CI-CD-Pipelines](../docs/wiki/08-CI-CD-Pipelines.md) for detailed pipeline flows and configuration.**

## Pipeline Types
1.  **Workload CI** (`workload-ci.yml`): Builds, scans (Trivy), and signs (Cosign) container images.
2.  **Infrastructure** (`terraform-validate.yml`): Validates and applies Terraform changes.
3.  **Golden Image** (`build-golden-image.yml`): Builds Windows 10 IoT Enterprise images via Packer.
