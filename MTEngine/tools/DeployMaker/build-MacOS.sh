#!/bin/sh
xcodebuild -workspace './DeployMaker.xcodeproj/project.xcworkspace' \
           -scheme 'DeployMaker' \
           -configuration 'Release' \
           CONFIGURATION_BUILD_DIR='./Release/'

