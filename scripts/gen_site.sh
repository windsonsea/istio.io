#!/bin/bash

# Copyright Istio Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -ex

mkdir -p generated/js generated/img tmp/js

tsc

babel --source-maps --minified --no-comments --presets minify \
  tmp/js/constants.js \
  tmp/js/utils.js \
  tmp/js/feedback.js \
  tmp/js/kbdnav.js \
  tmp/js/themes.js \
  tmp/js/menu.js \
  tmp/js/header.js \
  tmp/js/sidebar.js \
  tmp/js/tabset.js \
  tmp/js/prism.js \
  tmp/js/codeBlocks.js \
  tmp/js/links.js \
  tmp/js/resizeObserver.js \
  tmp/js/scroll.js \
  tmp/js/overlays.js \
  tmp/js/lang.js \
  tmp/js/callToAction.js \
  tmp/js/events.js \
  tmp/js/faq.js \
  --out-file generated/js/all.min.js

babel --source-maps --minified --no-comments --presets minify \
  tmp/js/headerAnimation.js \
  --out-file generated/js/headerAnimation.min.js

babel --source-maps --minified --no-comments \
  tmp/js/themes_init.js \
  --out-file generated/js/themes_init.min.js

svg-symbol-sprite -i src/icons -o generated/img/icons.svg --prefix ""