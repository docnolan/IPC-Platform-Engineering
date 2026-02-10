# Setting up Cosign Signing Keys in Azure DevOps

This guide explains how to generate a Cosign key pair and configure it as a Variable Group in Azure DevOps so your pipeline can sign container images.

## 1. Generate Key Pair
You need to generate a private/public key pair locally. You can do this on your Windows machine if you have `cosign` installed, or use a Linux terminal (like WSL).

```powershell
# Install Cosign (if not installed)
# winget install Sigstore.Cosign

# Generate keys
cosign generate-key-pair
```

You will be prompted to enter a password. **Remember this password**.
This will create two files:
- `cosign.key` (Private Key - ⚠️ KEEP SECRET)
- `cosign.pub` (Public Key - Safe to share)

## 2. Configure Azure DevOps Library

1.  Log in to your Azure DevOps Organization.
2.  Navigate to your Project: `IPC-Platform-Engineering`.
3.  In the left sidebar, go to **Pipelines** > **Library**.
4.  Click **+ Variable group**.

## 3. Create the `security-vars` Group

1.  **Variable group name**: Enter `security-vars`.
2.  Make sure "Allow access to all pipelines" is **checked**.
3.  Under **Variables**, click **+ Add** to add the following two variables:

| Name | Value | Secret? |
|------|-------|---------|
| `COSIGN_PASSWORD` | The password you typed when generating the keys. | 🔒 Click the lock icon to hide it. |
| `COSIGN_KEY` | Open `cosign.key` in a text editor (Notepad). Copy the **entire contents** (including `-----BEGIN ENCRYPTED COSIGN PRIVATE KEY-----`) and paste it here. | 🔒 Click the lock icon to hide it. |

4.  Click **Save**.

## 4. Verify
Your pipeline `pipelines/azure-pipelines-workloads.yml` references this group:

```yaml
variables:
- group: security-vars # Expects COSIGN_KEY and COSIGN_PASSWORD
```

When the pipeline runs:
- `$(COSIGN_PASSWORD)` will inject the password.
- `$(COSIGN_KEY)` will inject the private key PEM block, which `cosign sign` uses to sign the image.
