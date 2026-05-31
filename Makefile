CC=clang
CFLAGS=-arch arm64 -isysroot $(shell xcrun --sdk iphoneos --show-sdk-path) -mios-version-min=14.0 -fobjc-arc -dynamiclib -o VerifyLib.dylib VerifyLib.m -framework UIKit -framework Foundation

all:
    $(CC) $(CFLAGS)