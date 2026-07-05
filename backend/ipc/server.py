"""
IPC Server for sdi.coach

Task 1.2.1 [P]: Asyncio Unix socket server
Task 1.2.2 [S]: Client connection management
Task 1.2.3 [S]: Message dispatcher
Task 1.2.4 [S]: Graceful shutdown

This module provides an asyncio-based Unix domain socket server that:
- Listens on /tmp/sdicoach.sock for client connections
- Manages a single client (CLI) connection
- Routes incoming messages to registered handlers by type
- Handles graceful shutdown on SIGTERM/SIGINT signals
"""

from __future__ import annotations

import asyncio
import logging
import os
import signal
from pathlib import Path
from typing import Callable, Awaitable

from .protocol import (
    IPCMessage,
    MessageType,
    message_from_json,
    message_to_json,
)

# Type alias for message handlers
MessageHandler = Callable[[IPCMessage], Awaitable[None]]

logger = logging.getLogger(__name__)


class IPCServer:
    """Asyncio-based Unix domain socket server for IPC.

    Attributes:
        socket_path: Path to the Unix domain socket file
        is_running: Whether the server is currently running
        client_count: Number of connected clients
        has_client: Whether a client is connected
    """

    DEFAULT_SOCKET_PATH = "/tmp/sdicoach.sock"

    def __init__(self, socket_path: str = DEFAULT_SOCKET_PATH) -> None:
        """Initialize the IPC server.

        Args:
            socket_path: Path for the Unix domain socket (default: /tmp/sdicoach.sock)
        """
        self.socket_path = socket_path
        self._server: asyncio.Server | None = None
        self._handlers: dict[MessageType, MessageHandler] = {}
        self._client_writer: asyncio.StreamWriter | None = None
        self._client_reader: asyncio.StreamReader | None = None
        self._client_task: asyncio.Task | None = None
        self._shutdown_event = asyncio.Event()
        self._is_running = False

    @property
    def is_running(self) -> bool:
        """Return whether the server is currently running."""
        return self._is_running

    @property
    def client_count(self) -> int:
        """Return the number of connected clients."""
        return 1 if self._client_writer is not None else 0

    @property
    def has_client(self) -> bool:
        """Return whether a client is connected."""
        return self._client_writer is not None

    def register_handler(
        self, message_type: MessageType, handler: MessageHandler
    ) -> None:
        """Register a handler for a specific message type.

        Args:
            message_type: The MessageType to handle
            handler: Async function that will be called with the IPCMessage
        """
        self._handlers[message_type] = handler
        logger.debug(f"Registered handler for {message_type.value}")

    async def send_message(self, message: IPCMessage) -> None:
        """Send a message to the connected client.

        Args:
            message: The IPCMessage to send

        Raises:
            RuntimeError: If no client is connected
        """
        if self._client_writer is None:
            raise RuntimeError("No client connected")

        json_data = message_to_json(message) + "\n"
        self._client_writer.write(json_data.encode())
        await self._client_writer.drain()
        logger.debug(f"Sent message: {message.type.value}")

    async def start(self) -> None:
        """Start the server and listen for connections.

        This method will:
        1. Remove any existing socket file
        2. Create a new Unix domain socket server
        3. Accept client connections
        4. Run until shutdown is requested
        """
        # Remove existing socket file if present
        socket_path = Path(self.socket_path)
        if socket_path.exists():
            socket_path.unlink()
            logger.debug(f"Removed existing socket file: {self.socket_path}")

        # Create the server
        self._server = await asyncio.start_unix_server(
            self._handle_client,
            path=self.socket_path,
        )
        self._is_running = True
        logger.info(f"IPC server started on {self.socket_path}")

        # Wait for shutdown signal
        self._shutdown_event.clear()
        try:
            await self._shutdown_event.wait()
        finally:
            await self._cleanup()

    async def stop(self) -> None:
        """Stop the server gracefully.

        This will:
        1. Close all client connections
        2. Close the server
        3. Remove the socket file
        """
        logger.info("Stopping IPC server...")
        self._shutdown_event.set()

    async def shutdown(self) -> None:
        """Trigger graceful shutdown (alias for stop)."""
        await self.stop()

    def setup_signal_handlers(self) -> None:
        """Set up signal handlers for graceful shutdown.

        Handles SIGTERM and SIGINT signals.
        """
        loop = asyncio.get_event_loop()

        def signal_handler(sig: signal.Signals) -> None:
            logger.info(f"Received signal {sig.name}, initiating shutdown...")
            asyncio.create_task(self.shutdown())

        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, signal_handler, sig)

        logger.debug("Signal handlers registered for SIGTERM and SIGINT")

    async def _handle_client(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        """Handle a connected client.

        Args:
            reader: Stream reader for the client connection
            writer: Stream writer for the client connection
        """
        peer = writer.get_extra_info("peername")
        logger.info(f"Client connected: {peer}")

        # Store client reference
        self._client_reader = reader
        self._client_writer = writer

        try:
            await self._read_messages(reader)
        except asyncio.CancelledError:
            logger.debug("Client handler cancelled")
        except Exception as e:
            logger.error(f"Error handling client: {e}")
        finally:
            # Clean up client reference
            self._client_reader = None
            self._client_writer = None
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass
            logger.info(f"Client disconnected: {peer}")

    async def _read_messages(self, reader: asyncio.StreamReader) -> None:
        """Read and process messages from a client.

        Args:
            reader: Stream reader for the client connection
        """
        while True:
            try:
                # Read one line (newline-delimited JSON)
                data = await reader.readline()
                if not data:
                    # Client disconnected
                    break

                line = data.decode().strip()
                if not line:
                    continue

                # Parse and dispatch message
                try:
                    message = message_from_json(line)
                    await self._dispatch_message(message)
                except Exception as e:
                    logger.warning(f"Failed to process message: {e}")

            except asyncio.CancelledError:
                raise
            except Exception as e:
                logger.error(f"Error reading from client: {e}")
                break

    async def _dispatch_message(self, message: IPCMessage) -> None:
        """Dispatch a message to its registered handler.

        Args:
            message: The IPCMessage to dispatch
        """
        handler = self._handlers.get(message.type)
        if handler is None:
            logger.warning(f"No handler registered for message type: {message.type.value}")
            return

        # Run handler as a separate task so we can process new messages immediately
        # This allows tts_stop to be handled while interview_start is waiting for TTS
        asyncio.create_task(self._run_handler(handler, message))

    async def _run_handler(self, handler: MessageHandler, message: IPCMessage) -> None:
        """Run a message handler with error handling.

        Args:
            handler: The handler function to call
            message: The IPCMessage to process
        """
        try:
            await handler(message)
        except Exception as e:
            logger.error(f"Error in handler for {message.type.value}: {e}")

    async def _cleanup(self) -> None:
        """Clean up server resources."""
        self._is_running = False

        # Close client connection if active
        if self._client_writer is not None:
            self._client_writer.close()
            try:
                await self._client_writer.wait_closed()
            except Exception:
                pass
            self._client_writer = None
            self._client_reader = None

        # Close server
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
            self._server = None

        # Remove socket file
        socket_path = Path(self.socket_path)
        if socket_path.exists():
            socket_path.unlink()
            logger.debug(f"Removed socket file: {self.socket_path}")

        logger.info("IPC server stopped")
