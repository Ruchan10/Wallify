package com.google.android.datatransport.runtime;

import android.content.Context;

import com.google.android.datatransport.TransportFactory;

/**
 * No-op replacement for Google's datatransport library, which MediaPipe uses
 * to upload usage statistics. The real library is excluded in
 * app/build.gradle.kts; these classes cover only what MediaPipe's
 * RemoteLoggingClient calls, and every event is dropped.
 */
public final class TransportRuntime {
    private static final TransportRuntime INSTANCE = new TransportRuntime();
    private static final TransportFactory FACTORY =
            new TransportFactory() {
                @Override
                public <T> com.google.android.datatransport.Transport<T> getTransport(
                        String name,
                        Class<T> payloadType,
                        com.google.android.datatransport.Encoding encoding,
                        com.google.android.datatransport.Transformer<T, byte[]> transformer) {
                    return event -> {};
                }
            };

    private TransportRuntime() {}

    public static void initialize(Context context) {}

    public static TransportRuntime getInstance() {
        return INSTANCE;
    }

    public TransportFactory newFactory(Destination destination) {
        return FACTORY;
    }
}
