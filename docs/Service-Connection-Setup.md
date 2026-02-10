# Setting up the ACR Service Connection

The error `service connection <your-acr-name> which could not be found` means Azure DevOps doesn't have permission to push to your Container Registry yet. You need to create a "Service Connection" to link them.

## Steps

1.  **Go to Project Settings**:
    *   In Azure DevOps, click **Project settings** in the bottom-left corner of the sidebar.

2.  **Navigate to Service Connections**:
    *   Under the **Pipelines** section, click **Service connections**.
    *   Click the **New service connection** button (top right).

3.  **Choose Connection Type**:
    *   Select **Docker Registry**.
    *   Click **Next**.

4.  **Choose Registry Type**:
    *   Select **Azure Container Registry**.
    *   Click **Next**.

5.  **Configure Details**:
    *   **Subscription**: Select your Azure subscription.
    *   **Registry**: Select `<your-acr-name>` (it should appear in the dropdown).
    *   **Service connection name**: Enter `<your-acr-name>`.
        *   ⚠️ **Critical**: This must match exactly, or the pipeline won't find it.
    *   **Security**: Check the box **"Grant access permission to all pipelines"**.

6.  **Save**:
    *   Click **Save**.

## Retry Pipeline
Once saved, go back to your Pipeline run and click **Run new** or **Retry**. It should now verify successfully.
