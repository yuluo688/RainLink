package dev.rainlink.rainlink.core;

import java.io.InputStream;
import java.io.OutputStream;
import java.io.ByteArrayOutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;

/** A shell-UID HTTP client that keeps its write side open until the response ends. */
public final class TunnelRequest {
    private static final int MAX_TIMEOUT_SECONDS = 60;
    private static final long MAX_RESPONSE_BYTES = 64L * 1024 * 1024;
    private static final int ACCOUNTING_PAYLOAD_BYTES = 32768;
    private static final byte[] ACCOUNTING_MARKER =
            "RainLink Android tunnel fixture\n".getBytes(StandardCharsets.US_ASCII);
    private static final int ACCOUNTING_BODY_BYTES = ACCOUNTING_MARKER.length + ACCOUNTING_PAYLOAD_BYTES;

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
            // Verify bytes in the actual client and emit a small receipt.
            // The target waits for this receipt before closing its socket.
            ByteArrayOutputStream accounting = path.equals("/traffic-accounting")
                    ? new ByteArrayOutputStream() : null;
            int length;
            while ((length = input.read(buffer)) != -1) {
                total += length;
                if (total > MAX_RESPONSE_BYTES) throw new IllegalStateException("QA response exceeded its limit");
                if (accounting != null) {
                    accounting.write(buffer, 0, length);
                    String current = accounting.toString("US-ASCII");
                    int boundary = current.indexOf("\r\n\r\n");
                    if (boundary >= 0 && accounting.size() >= boundary + 4 + ACCOUNTING_BODY_BYTES) {
                        verifyAccounting(accounting.toByteArray());
                        output.write('R');
                        output.flush();
                        return;
                    }
                } else {
                    System.out.write(buffer, 0, length);
                    System.out.flush();
                }
            }
            if (accounting != null) {
                throw new IllegalStateException("Accounting response ended before its complete-body receipt");
            }
        }
    }

    private static void verifyAccounting(byte[] response) throws Exception {
        String text = new String(response, StandardCharsets.US_ASCII);
        int boundary = text.indexOf("\r\n\r\n");
        if (boundary < 0 || !(text.startsWith("HTTP/1.0 200 ") || text.startsWith("HTTP/1.1 200 "))) {
            throw new IllegalStateException("Accounting fixture returned an invalid HTTP response");
        }
        byte[] expected = new byte[ACCOUNTING_BODY_BYTES];
        Arrays.fill(expected, (byte) 'x');
        System.arraycopy(ACCOUNTING_MARKER, 0, expected, 0, ACCOUNTING_MARKER.length);
        byte[] body = Arrays.copyOfRange(response, boundary + 4, response.length);
        if (!Arrays.equals(body, expected)) {
            throw new IllegalStateException("Accounting fixture payload differs: " + body.length);
        }
        StringBuilder digest = new StringBuilder();
        for (byte value : MessageDigest.getInstance("SHA-256").digest(body)) {
            digest.append(String.format(java.util.Locale.ROOT, "%02x", value & 0xff));
        }
        System.out.println("{\"bytes\":" + body.length + ",\"sha256\":\"" + digest + "\"}");
        System.out.flush();
    }
}
