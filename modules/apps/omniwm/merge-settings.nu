#!/usr/bin/env nu

# ---------------------------------------------------------------------------
# Adapted from ryoppippi/dotfiles
#   nix/modules/darwin/programs/omniwm/merge-settings.nu
#   https://github.com/ryoppippi/dotfiles
#
# MIT License
#
# Copyright (c) 2022 Ryotaro "Justin" Kimura
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ---------------------------------------------------------------------------
#
# Overlay the repository's OmniWM settings onto the live file, keeping the
# monitor settings and anything else the app owns.
#
# OmniWM has no include mechanism — `~/.config/omniwm/settings.toml` is its only
# settings source, and the app rewrites that file wholesale whenever the GUI
# saves — so activation has to write the whole file back. It contributes only
# the keys the template actually defines, though: a key the app writes and the
# template says nothing about is left alone rather than dropped.
#
# The monitor settings are the one case where the template does define a key and
# still loses. They are keyed by physical display UUID, which makes them a
# description of the machine and the desk it sits on rather than of this
# configuration. ogasawara (Mac mini + 外部モニタ) と tanegashima (MacBook Air
# 内蔵のみ) は profiles/mac-workstation.nix を共有しているので、UUID をコミット
# すると必ずどちらかで間違う。テンプレは空の placeholder だけを持ち、overlay
# からは明示的に落として live 値を残す。
#
# Usage: merge-settings.nu <template> <live>

# Top-level settings the GUI owns. Everything else the template defines wins.
const GUI_OWNED_KEYS = [
    monitorBarOverrides
    monitorDwindleOverrides
    monitorGapOverrides
    monitorNiriOverrides
    monitorOrientationOverrides
    monitorRoutingOverrides
]

# Overlay $overlay onto the piped record, recursing into keys both sides hold as
# records. Leaf values from $overlay win; keys absent from it keep their live
# value. Recursing is what lets a template key sit beside an app-owned one
# within the same table instead of the whole table being replaced.
def deep-merge [overlay: record]: record -> record {
    let base = $in

    $overlay
    | columns
    | reduce --fold $base {|key, merged|
        let new = $overlay | get $key
        let old = $merged | get --optional $key

        let both_records = (
            ($old | describe | str starts-with 'record')
            and ($new | describe | str starts-with 'record')
        )

        $merged | upsert $key (if $both_records { $old | deep-merge $new } else { $new })
    }
}

# Drop the settings the GUI owns from the piped template, so merging leaves the
# live file's values in place. `[routing] mode` selects between the macOS
# arrangement and the custom map that `monitorRoutingOverrides` describes, so it
# is monitor state as well — just nested rather than top-level.
def drop-gui-owned []: record -> record {
    let template = $in | reject --optional ...$GUI_OWNED_KEYS

    if 'routing' in $template {
        $template | update routing { reject --optional mode }
    } else {
        $template
    }
}

def main [template: path, live: path]: nothing -> nothing {
    if not ($template | path exists) {
        error make {msg: $"OmniWM settings template is missing: ($template)"}
    }

    let template_settings = open --raw $template | from toml

    # A first-ever activation has no live file to preserve anything from, so the
    # template's monitor placeholders are all there is to write.
    let merged = if ($live | path exists) {
        open --raw $live | from toml | deep-merge ($template_settings | drop-gui-owned)
    } else {
        $template_settings
    }

    mkdir ($live | path dirname)

    # OmniWM reads this file while running, so swap it in whole rather than
    # letting the app observe a half-written one.
    let staged = $live | path parse | upsert extension 'toml.nix-tmp' | path join
    $merged | to toml | save --force $staged
    mv --force $staged $live
}
