# Contributing to Maelstrom Smart Contracts

First off, thank you for considering contributing to Maelstrom! We value your time and effort, and we want to make contributing as easy and transparent as possible.

This guide details how to set up your development environment, our coding standards, and the process for submitting Pull Requests (PRs).

## 🛠 Prerequisites

This project is built using **Foundry** and uses **Node.js** for linting and formatting. Ensure you have the following installed:

1.  **Foundry**: You will need `forge`, `cast`, and `anvil`.
    * [Installation Guide](https://book.getfoundry.sh/getting-started/installation)
2.  **Node.js & npm**: Required for running Prettier plugins.
    * [Download Node.js](https://nodejs.org/)

## 🚀 Getting Started

1.  **Fork the repository** on GitHub.
2.  **Clone your fork** locally:
3.  **Install Submodules (Foundry)**:
    ```bash
    forge install
    ```
4.  **Install Node Dependencies** (for formatting):
    ```bash
    npm install
    ```

## ⚠️ Important: Code Formatting & Style

We enforce strict code formatting to ensure consistency across the codebase. We use **Prettier** with the Solidity plugin.

> [!IMPORTANT]
> **You MUST format your code before pushing or committing.**
> CI pipelines may fail if the code does not meet the style guidelines.

### Formatting Commands
We have configured scripts in `package.json` to make this easy:

* **Format All Files (Recommended)**:
    Runs Prettier on all `.sol` files in the project. Run this before every commit.
    ```bash
    npm run sol-fmt-all
    ```

* **Format Specific File**:
    If you only want to format the file you are working on, you can run the standard prettier command manually:
    ```bash
    npx prettier --write "src/YourFile.sol" --plugin=prettier-plugin-solidity
    ```

* **Check Formatting**:
    To verify if files are correctly formatted without modifying them:
    ```bash
    npm run sol-check-all
    ```

## 🧪 Testing

We use Foundry for testing. Please ensure all tests pass before submitting your PR.

* **Run Tests**:
    ```bash
    forge test
    ```
* **Run Specific Test**:
    ```bash
    forge test --match-test testName
    ```

## 📥 Submission Guidelines

### 1. Create a Branch
Create a new branch for your feature or fix. Do not work directly on `main`.
```bash
git checkout -b feature/amazing-feature
```
