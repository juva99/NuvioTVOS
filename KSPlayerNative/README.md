# KSPlayer Native Backend

This package contains the dependency-free `KSAVPlayer` integration surface used
by Nuvio, adapted from KSPlayer 2.3.4. The FFmpeg `KSMEPlayer` backend is omitted
because Nuvio already uses MPVKit and both upstream packages export conflicting
FFmpeg module names.

Upstream: https://github.com/kingslay/KSPlayer
License: GPL-3.0, matching the parent Nuvio project.
