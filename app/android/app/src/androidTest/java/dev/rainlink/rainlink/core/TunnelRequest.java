package dev.rainlink.rainlink.core;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

/** A shell-UID HTTP client that keeps its write side open until the response ends. */
public final class TunnelRequest {
    private static final int MAX_TIMEOUT_SECONDS = 60;
    private static final long MAX_RESPONSE_BYTES = 64L * 1024 * 1024;

    private TunnelRequest() {}

    public static void main(String[] arguments) throws Exception {
        if (arguments.length != 4) throw new IllegalArgumentException("Expected address, timeout, path and port");
        String address = arguments[0];
        int seconds = Integer.parseInt(arguments[1]);
        String path = arguments[2];
        int port = Integer.parseInt(arguments[3]);
        if (seconds < 1 || seconds > MAX_TIMEOUT_SECONDS || port < 1 || port > 65535 ||
                !path.startsWith("/") || path.length() > 256 || path.contains("\r") || path.contains("\n")) {
            throw new IllegalArgumentException("Invalid QA request");
        }
        int timeout = seconds * 1000;
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(address, port), timeout);
            socket.setSoTimeout(timeout);
            OutputStream output = socket.getOutputStream();
            String headers = "GET " + path + " HTTP/1.1\r\nHost: rainlink.test\r\n" +
                    (path.equals("/hold") ? "Content-Length: 67108864\r\n" : "") +
                    "Connection: close\r\n\r\n";
            output.write(headers.getBytes(StandardCharsets.US_ASCII));
            output.flush();
            // Closing a producer pipe after one second previously half-closed
            // during delayed proxy handshakes. Ordinary clients await the reply.
            InputStream input = socket.getInputStream();
            byte[] buffer = new byte[8192];
            long total = 0;
            int length;
            while ((length = input.read(buffer)) != -1) {
                total += length;
                if (total > MAX_RESPONSE_BYTES) throw new IllegalStateException("QA response exceeded its limit");
                System.out.write(buffer, 0, length);
                System.out.flush();
            }
        }
    }
}
