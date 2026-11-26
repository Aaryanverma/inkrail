"""Linux host for the Inkrail writing desk.

The editor itself is the cross-platform web desk under ``packaging/windows/ui``.
This package serves it from a loopback-only HTTP server and provides the native
desktop services (file dialogs, window lifecycle, PDF printing) that the desk
asks for through its RPC bridge.
"""

__version__ = "0.1.2"
