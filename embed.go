// Package hvskills carries the skill set inside the hv binary. It is the only
// Go package at the module root because go:embed cannot reach a parent
// directory; internal/skills owns everything done with the files.
package hvskills

import "embed"

// FS holds every skill's markdown (hv-*/*.md) and the shared references
// (references/*.md).
//
//go:embed hv-*/*.md references/*.md
var FS embed.FS
