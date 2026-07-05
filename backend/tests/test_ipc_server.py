"""
Tests for IPC Server (Phase 1.2)

Task 1.2.1 [P]: Asyncio Unix socket server
Task 1.2.2 [S]: Client connection management
Task 1.2.3 [S]: Message dispatcher
Task 1.2.4 [S]: Graceful shutdown
"""

import asyncio
import os
import signal
import tempfile
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

import pytest

from ipc.protocol import (
    IPCMessage,
    MessageType,
    create_handshake_request,
    create_handshake_response,
    create_interview_start_message,
    create_transcription_message,
    message_from_json,
    message_to_json,
)
from ipc.server import IPCServer


# =============================================================================
# Task 1.2.1: Asyncio Unix socket server
# =============================================================================


class TestIPCServerInit:
    """Test IPCServer initialization."""

    def test_server_init_with_default_socket_path(self):
        """Server should use default socket path /tmp/sdicoach.sock."""
        server = IPCServer()
        assert server.socket_path == "/tmp/sdicoach.sock"

    def test_server_init_with_custom_socket_path(self):
        """Server should accept custom socket path."""
        custom_path = "/tmp/custom.sock"
        server = IPCServer(socket_path=custom_path)
        assert server.socket_path == custom_path

    def test_server_not_running_initially(self):
        """Server should not be running after initialization."""
        server = IPCServer()
        assert not server.is_running


class TestIPCServerStart:
    """Test IPCServer start functionality."""

    @pytest.fixture
    def temp_socket_path(self):
        """Create a temporary socket path for testing."""
        with tempfile.TemporaryDirectory() as tmpdir:
            yield os.path.join(tmpdir, "test.sock")

    async def test_server_creates_socket_file_on_start(self, temp_socket_path):
        """Server should create socket file when started."""
        server = IPCServer(socket_path=temp_socket_path)

        # Start server in background
        server_task = asyncio.create_task(server.start())

        # Wait for server to start
        await asyncio.sleep(0.1)

        try:
            assert server.is_running
            assert Path(temp_socket_path).exists()
        finally:
            await server.stop()
            await server_task

    async def test_server_removes_existing_socket_on_start(self, temp_socket_path):
        """Server should remove existing socket file before starting."""
        # Create an existing socket file
        Path(temp_socket_path).touch()
        assert Path(temp_socket_path).exists()

        server = IPCServer(socket_path=temp_socket_path)
        server_task = asyncio.create_task(server.start())

        await asyncio.sleep(0.1)

        try:
            assert server.is_running
        finally:
            await server.stop()
            await server_task

    async def test_server_accepts_client_connection(self, temp_socket_path):
        """Server should accept client connections."""
        server = IPCServer(socket_path=temp_socket_path)
        server_task = asyncio.create_task(server.start())

        await asyncio.sleep(0.1)

        try:
            # Connect a client
            reader, writer = await asyncio.open_unix_connection(temp_socket_path)
            assert reader is not None
            assert writer is not None
            writer.close()
            await writer.wait_closed()
        finally:
            await server.stop()
            await server_task


# =============================================================================
# Task 1.2.2: Client connection management
# =============================================================================


class TestClientConnectionManagement:
    """Test client connection management."""

    @pytest.fixture
    def temp_socket_path(self):
        """Create a temporary socket path for testing."""
        with tempfile.TemporaryDirectory() as tmpdir:
            yield os.path.join(tmpdir, "test.sock")

    async def test_server_tracks_connected_client(self, temp_socket_path):
        """Server should track connected clients."""
        server = IPCServer(socket_path=temp_socket_path)
        server_task = asyncio.create_task(server.start())

        await asyncio.sleep(0.1)

        try:
            # Initially no clients
            assert server.client_count == 0

            # Connect a client
            reader, writer = await asyncio.open_unix_connection(temp_socket_path)
            await asyncio.sleep(0.1)

            # Client should be tracked
            assert server.client_count == 1

            writer.close()
            await writer.wait_closed()
        finally:
            await server.stop()
            await server_task

    async def test_server_handles_client_disconnect(self, temp_socket_path):
        """Server should handle client disconnect gracefully."""
        server = IPCServer(socket_path=temp_socket_path)
        server_task = asyncio.create_task(server.start())

        await asyncio.sleep(0.1)

        try:
            # Connect a client
            reader, writer = await asyncio.open_unix_connection(temp_socket_path)
            await asyncio.sleep(0.1)
            assert server.client_count == 1

            # Disconnect client
            writer.close()
            await writer.wait_closed()
            await asyncio.sleep(0.1)

            # Client should be removed
            assert server.client_count == 0
        finally:
            await server.stop()
            await server_task

    async def test_server_supports_single_client(self, temp_socket_path):
        """Server should support single client connection (CLI)."""
        server = IPCServer(socket_path=temp_socket_path)
        server_task = asyncio.create_task(server.start())

        await asyncio.sleep(0.1)

        try:
            # Connect first client
            reader1, writer1 = await asyncio.open_unix_connection(temp_socket_path)
            await asyncio.sleep(0.1)
            assert server.client_count == 1

            # First connection should work
            assert server.has_client

            writer1.close()
            await writer1.wait_closed()
        finally:
            await server.stop()
            await server_task


# =============================================================================
# Task 1.2.3: Message dispatcher
# =============================================================================


class TestMessageDispatcher:
    """Test message dispatcher functionality."""

    @pytest.fixture
    def temp_socket_path(self):
        """Create a temporary socket path for testing."""
        with tempfile.TemporaryDirectory() as tmpdir:
            yield os.path.join(tmpdir, "test.sock")

    def test_register_handler(self):
        """Server should allow registering handlers for message types."""
        server = IPCServer()
        handler = AsyncMock()

        server.register_handler(MessageType.INTERVIEW_START, handler)

        assert MessageType.INTERVIEW_START in server._handlers
        assert server._handlers[MessageType.INTERVIEW_START] == handler

    def test_register_multiple_handlers(self):
        """Server should allow registering multiple handlers for different types."""
        server = IPCServer()
        handler1 = AsyncMock()
        handler2 = AsyncMock()

        server.register_handler(MessageType.INTERVIEW_START, handler1)
        server.register_handler(MessageType.AUDIO_DATA, handler2)

        assert len(server._handlers) == 2

    async def test_message_routed_to_handler(self, temp_socket_path):
        """Incoming messages should be routed to registered handlers."""
        server = IPCServer(socket_path=temp_socket_path)
        handler = AsyncMock()
        server.register_handler(MessageType.INTERVIEW_START, handler)

        server_task = asyncio.create_task(server.start())
        await asyncio.sleep(0.1)

        try:
            # Connect and send a message
            reader, writer = await asyncio.open_unix_connection(temp_socket_path)

            message = create_interview_start_message(question="Design a URL shortener")
            json_data = message_to_json(message) + "\n"
            writer.write(json_data.encode())
            await writer.drain()

            await asyncio.sleep(0.1)

            # Handler should have been called
            handler.assert_called_once()
            call_args = handler.call_args[0][0]
            assert isinstance(call_args, IPCMessage)
            assert call_args.type == MessageType.INTERVIEW_START

            writer.close()
            await writer.wait_closed()
        finally:
            await server.stop()
            await server_task

    async def test_unhandled_message_type_ignored(self, temp_socket_path):
        """Messages without registered handlers should be logged but not crash."""
        server = IPCServer(socket_path=temp_socket_path)
        # No handler registered

        server_task = asyncio.create_task(server.start())
        await asyncio.sleep(0.1)

        try:
            reader, writer = await asyncio.open_unix_connection(temp_socket_path)

            message = create_interview_start_message(question="Test")
            json_data = message_to_json(message) + "\n"
            writer.write(json_data.encode())
            await writer.drain()

            await asyncio.sleep(0.1)

            # Server should still be running
            assert server.is_running

            writer.close()
            await writer.wait_closed()
        finally:
            await server.stop()
            await server_task


class TestSendMessage:
    """Test sending messages to client."""

    @pytest.fixture
    def temp_socket_path(self):
        """Create a temporary socket path for testing."""
        with tempfile.TemporaryDirectory() as tmpdir:
            yield os.path.join(tmpdir, "test.sock")

    async def test_send_message_to_client(self, temp_socket_path):
        """Server should be able to send messages to connected client."""
        server = IPCServer(socket_path=temp_socket_path)
        server_task = asyncio.create_task(server.start())

        await asyncio.sleep(0.1)

        try:
            reader, writer = await asyncio.open_unix_connection(temp_socket_path)
            await asyncio.sleep(0.1)

            # Server sends a message
            response = create_transcription_message(text="Hello", is_final=True)
            await server.send_message(response)

            # Client should receive the message
            data = await asyncio.wait_for(reader.readline(), timeout=1.0)
            received = message_from_json(data.decode().strip())

            assert received.type == MessageType.TRANSCRIPTION
            assert received.payload["text"] == "Hello"

            writer.close()
            await writer.wait_closed()
        finally:
            await server.stop()
            await server_task

    async def test_send_message_no_client_raises_error(self, temp_socket_path):
        """Sending message when no client connected should raise an error."""
        server = IPCServer(socket_path=temp_socket_path)
        server_task = asyncio.create_task(server.start())

        await asyncio.sleep(0.1)

        try:
            message = create_transcription_message(text="Hello", is_final=True)
            with pytest.raises(RuntimeError, match="No client connected"):
                await server.send_message(message)
        finally:
            await server.stop()
            await server_task


# =============================================================================
# Task 1.2.4: Graceful shutdown
# =============================================================================


class TestGracefulShutdown:
    """Test graceful shutdown functionality."""

    @pytest.fixture
    def temp_socket_path(self):
        """Create a temporary socket path for testing."""
        with tempfile.TemporaryDirectory() as tmpdir:
            yield os.path.join(tmpdir, "test.sock")

    async def test_stop_closes_server(self, temp_socket_path):
        """stop() should close the server."""
        server = IPCServer(socket_path=temp_socket_path)
        server_task = asyncio.create_task(server.start())

        await asyncio.sleep(0.1)
        assert server.is_running

        await server.stop()
        await server_task

        assert not server.is_running

    async def test_stop_removes_socket_file(self, temp_socket_path):
        """stop() should remove the socket file."""
        server = IPCServer(socket_path=temp_socket_path)
        server_task = asyncio.create_task(server.start())

        await asyncio.sleep(0.1)
        assert Path(temp_socket_path).exists()

        await server.stop()
        await server_task

        assert not Path(temp_socket_path).exists()

    async def test_stop_closes_client_connections(self, temp_socket_path):
        """stop() should close all client connections."""
        server = IPCServer(socket_path=temp_socket_path)
        server_task = asyncio.create_task(server.start())

        await asyncio.sleep(0.1)

        # Connect client
        reader, writer = await asyncio.open_unix_connection(temp_socket_path)
        await asyncio.sleep(0.1)
        assert server.client_count == 1

        await server.stop()
        await server_task

        assert server.client_count == 0

    def test_setup_signal_handlers(self):
        """Server should support setting up signal handlers."""
        server = IPCServer()

        # Should not raise
        server.setup_signal_handlers()

    async def test_signal_handler_stops_server(self, temp_socket_path):
        """Signal handler should trigger graceful shutdown."""
        server = IPCServer(socket_path=temp_socket_path)

        server_task = asyncio.create_task(server.start())
        await asyncio.sleep(0.1)

        assert server.is_running

        # Trigger shutdown via internal method (simulating signal)
        await server.shutdown()
        await server_task

        assert not server.is_running


# =============================================================================
# Integration tests
# =============================================================================


class TestIPCServerIntegration:
    """Integration tests for IPC Server."""

    @pytest.fixture
    def temp_socket_path(self):
        """Create a temporary socket path for testing."""
        with tempfile.TemporaryDirectory() as tmpdir:
            yield os.path.join(tmpdir, "test.sock")

    async def test_full_message_exchange(self, temp_socket_path):
        """Test complete message exchange between client and server."""
        server = IPCServer(socket_path=temp_socket_path)
        received_messages = []

        async def message_handler(message: IPCMessage):
            received_messages.append(message)

        server.register_handler(MessageType.INTERVIEW_START, message_handler)

        server_task = asyncio.create_task(server.start())
        await asyncio.sleep(0.1)

        try:
            # Connect client
            reader, writer = await asyncio.open_unix_connection(temp_socket_path)

            # Client sends interview start
            start_msg = create_interview_start_message(
                question="Design a distributed cache"
            )
            writer.write((message_to_json(start_msg) + "\n").encode())
            await writer.drain()

            await asyncio.sleep(0.1)

            # Verify message was received
            assert len(received_messages) == 1
            assert received_messages[0].payload["question"] == "Design a distributed cache"

            # Server sends response
            response = create_transcription_message(text="Starting interview...", is_final=True)
            await server.send_message(response)

            # Client receives response
            data = await asyncio.wait_for(reader.readline(), timeout=1.0)
            received = message_from_json(data.decode().strip())
            assert received.type == MessageType.TRANSCRIPTION

            writer.close()
            await writer.wait_closed()
        finally:
            await server.stop()
            await server_task

    async def test_multiple_messages_in_sequence(self, temp_socket_path):
        """Test handling multiple messages in sequence."""
        server = IPCServer(socket_path=temp_socket_path)
        received_messages = []

        async def handler(message: IPCMessage):
            received_messages.append(message)

        server.register_handler(MessageType.INTERVIEW_START, handler)

        server_task = asyncio.create_task(server.start())
        await asyncio.sleep(0.1)

        try:
            reader, writer = await asyncio.open_unix_connection(temp_socket_path)

            # Send multiple messages
            for i in range(3):
                msg = create_interview_start_message(question=f"Question {i}")
                writer.write((message_to_json(msg) + "\n").encode())
                await writer.drain()
                await asyncio.sleep(0.05)

            await asyncio.sleep(0.1)

            # All messages should be received
            assert len(received_messages) == 3

            writer.close()
            await writer.wait_closed()
        finally:
            await server.stop()
            await server_task
