package com.google.android.datatransport;

public interface TransportFactory {
    <T> Transport<T> getTransport(
            String name, Class<T> payloadType, Encoding encoding, Transformer<T, byte[]> transformer);
}
