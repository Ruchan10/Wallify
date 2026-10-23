package com.google.android.datatransport;

public final class Event<T> {
    private Event() {}

    public static <T> Event<T> ofData(T payload) {
        return new Event<>();
    }
}
