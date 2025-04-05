# Building the Local Crawl4AI Docker Image with GPU Support

This document provides instructions on how to build the `crawl4ai` Docker image locally, specifically enabling GPU support for use with the provided `docker-compose.yml` configuration.

## Prerequisites

1.  **Git:** Required to clone the repository.
2.  **Docker:** Ensure Docker is installed and running (version 20.10.0 or higher).
3.  **Nvidia Container Toolkit:** Necessary for Docker to utilize Nvidia GPUs. Follow the official installation guide for your Linux distribution: [https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
4.  **Buildx (Optional but Recommended):** For multi-platform builds if needed. `docker buildx create --use`

## Build Steps

1.  **Clone the Repository:**
    Open your terminal and clone the `crawl4ai` repository:
    ```bash
    git clone https://github.com/unclecode/crawl4ai.git
    ```

2.  **Navigate to the Project Root Directory:**
    Change into the cloned repository's root directory:
    ```bash
    cd crawl4ai
    ```

3.  **Build the GPU-Enabled Image:**
    Run the following command **from the project root directory (`crawl4ai/`)** to build the Docker image. This command specifically enables GPU support and tags the image as `crawl4ai:latest`, which matches the `docker-compose.yml` file.
    ```bash
    docker build --platform=linux/amd64 --no-cache -t crawl4ai:latest --build-arg ENABLE_GPU=true .
    ```
    *   `--platform=linux/amd64`: Specifies the target platform (adjust if needed, e.g., `linux/arm64`).
    *   `--no-cache`: Ensures you are using the latest base images and dependencies. Remove this for faster subsequent builds if no fundamental changes were made.
    *   `-t crawl4ai:latest`: Tags the built image as `crawl4ai` with the `latest` tag.
    *   `--build-arg ENABLE_GPU=true`: This is crucial for enabling Nvidia GPU support within the container.
    *   `.`: Specifies the current directory (the project root `crawl4ai/`) as the build context, where the Dockerfile is located.

4.  **(Optional) Configure API Keys:**
    If you plan to use LLM features within `crawl4ai`, create a `.llm.env` file in the `crawl4ai` project root directory (or wherever you plan to manage your environment variables) with your API keys:
    ```env
    # .llm.env
    OPENAI_API_KEY=sk-your-openai-key
    ANTHROPIC_API_KEY=your-anthropic-key
    DEEPSEEK_API_KEY=your-deepseek-key
    # Add other keys as needed
    ```
    The `docker-compose.yml` file is set up to potentially use these variables if defined in your main `.env` file or passed directly.

## Next Steps

Once the image is built successfully with the tag `crawl4ai:latest`, you can return to the directory containing your `docker-compose.yml` file and run `docker-compose up -d` to start the services, including the GPU-enabled `crawl4ai`.
