// Package marker is the one place that writes and recognises the hidden
// `<!-- hv:... -->` line hv puts on every comment it posts. It has no
// internal dependencies so any package can use it.
package marker

import "strings"

// Prefix opens every marker hv writes.
const Prefix = "<!-- hv:"

// Line renders `<!-- hv:<kind>[ <arg>...] -->`.
func Line(kind string, args ...string) string {
	s := Prefix + kind
	for _, a := range args {
		s += " " + a
	}
	return s + " -->"
}

// Has reports whether body carries an hv marker, so hv posted it.
func Has(body string) bool { return strings.Contains(body, Prefix) }
