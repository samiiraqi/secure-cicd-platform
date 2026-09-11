const express = require("express");

const app = express();
const port = process.env.PORT || 8080;

app.get("/health", (_req, res) => {
  res.status(200).json({ status: "ok" });
});

app.get("/", (_req, res) => {
  res.status(200).json({
    message: "Secure CI/CD Platform - demo app",
    environment: process.env.APP_ENV || "unknown",
  });
});

app.listen(port, () => {
  console.log(`Listening on port ${port}`);
});
