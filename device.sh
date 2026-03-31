#!/bin/bash

xcodebuild test \
  -project droidrun-ios-portal.xcodeproj \
  -scheme droidrun-ios-portal \
  -destination "platform=iOS,id=$1" \
  -only-testing "Droidrun Server"
