# Registering the Pipeline in Azure DevOps

Even though the YAML file is in the repo, you must tell Azure DevOps to treat it as a pipeline. This is a one-time setup.

1.  **Navigate to Pipelines**:
    *   In your Azure DevOps project, click **Pipelines** in the left sidebar.
    *   Click the **New pipeline** button (top right).

2.  **Connect**:
    *   Select **Azure Repos Git**.

3.  **Select**:
    *   Click on your repository: `IPC-Platform-Engineering`.

4.  **Configure**:
    *   Select **Existing Azure Pipelines YAML file**.
    *   **Branch**: `main`.
    *   **Path**: Select `/pipelines/azure-pipelines-workloads.yml` from the dropdown.
    *   Click **Continue**.

5.  **Finish**:
    *   Click the **Run** button (or the dropdown arrow next to it -> **Save**) to finish the setup.

Once saved, the pipeline will appear in your list and will automatically trigger whenever you push changes to the `docker/` folder.
