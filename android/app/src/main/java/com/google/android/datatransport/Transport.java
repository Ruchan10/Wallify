package com.google.android.datatransport;

public interface Transport<T> {
    void send(Event<T> event);
}
