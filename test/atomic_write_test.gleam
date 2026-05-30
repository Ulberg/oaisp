import gleam/result
import oaisp/internal/atomic_write
import oaisp/internal/fs

pub fn writes_then_renames_test() {
  let path = "build/atomic_write_test.json"
  let _ = fs.delete(path)

  let assert Ok(Nil) = atomic_write.write(path, "{\"ok\":true}")

  let assert Ok(content) = fs.read(path)
  assert content == "{\"ok\":true}"
  // The temp file has been renamed away, not left behind.
  assert result.is_error(fs.read(path <> ".oaisp.tmp"))

  let _ = fs.delete(path)
  Nil
}
