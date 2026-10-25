#pragma once

// No Arduino headers: the OpenPLC block includes this and is compiled on a
// host as well as for the board. The implementation is what is guarded.
#include <stdint.h>

/**
 * Serves the Node UIO's web interface.
 *
 * Reads and writes the board through NodeUioAPI, the same surface the OpenPLC
 * blocks use, so the two cannot disagree about what a value means.
 *
 * It does not own the radio. Something has to bring a network up first — the
 * NETWORK block under OpenPLC, or the sketch itself standalone — and this binds
 * a port on whatever is there. `running()` says whether it managed to.
 *
 * The page comes from LittleFS at /www. That is a filesystem image, not part of
 * the firmware, so it is uploaded separately with PlatformIO's Upload
 * Filesystem Image.
 */
class NodeWebUI {
public:
  explicit NodeWebUI(uint16_t port = 80);
  ~NodeWebUI();

  /** Mounts the filesystem and starts serving. False when there is no network. */
  bool begin();

  /** Serves, and pushes state to connected clients. Call each cycle. */
  void update();

  bool running() const;

  /** Browsers on the live feed. */
  uint32_t clients() const;

private:
  NodeWebUI(const NodeWebUI&) = delete;
  NodeWebUI& operator=(const NodeWebUI&) = delete;

  struct Impl;
  Impl* _impl;
};
