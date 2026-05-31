//// Atomic file writes: write a sibling temp file then rename it over the
//// target, so a concurrent reader never observes a half-written document.

import gleam/result
import oaisp/internal/fs

/// Write `contents` to `path` atomically. The temp file sits beside the target
/// (same filesystem), so the rename is atomic. The error is the OTP `file`
/// reason.
pub fn write(path: String, contents: String) -> Result(Nil, String) {
  let temp = path <> ".oaisp.tmp"
  use _ <- result.try(fs.write(temp, contents))
  fs.rename(temp, path)
}
