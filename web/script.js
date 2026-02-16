const copyButton = document.getElementById("copy-btn");
const command = document.getElementById("install-cmd")?.innerText?.trim() ?? "";

copyButton?.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(command);
    copyButton.textContent = "Copied";
    setTimeout(() => {
      copyButton.textContent = "Copy";
    }, 1400);
  } catch {
    copyButton.textContent = "Failed";
    setTimeout(() => {
      copyButton.textContent = "Copy";
    }, 1400);
  }
});
