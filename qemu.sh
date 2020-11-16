#!/bin/bash

qemu-system-x86_64 \
    -cdrom x.iso \
    -boot order=d \
    -drive file=disk,format=raw \
    -usb \
    -device usb-tablet

