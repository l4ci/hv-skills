package backlog

// The issue backend's write side is not ported yet; a later PR replaces these
// stubs. Each wraps ErrNotPorted, which the CLI maps to exit 71.

func notPorted(verb string) error {
	return errf(ErrNotPorted, "issue mode for %s not ported yet", verb)
}

// Create is not ported.
func (b *Issues) Create(CreateInput) (CreateResult, error) {
	return CreateResult{}, notPorted("item create")
}

// SetField is not ported.
func (b *Issues) SetField(string, string, string) (bool, error) {
	return false, notPorted("item field set")
}

// Complete is not ported.
func (b *Issues) Complete(string, CompleteInput) (bool, error) {
	return false, notPorted("item complete")
}

// Reopen is not ported.
func (b *Issues) Reopen(string) (bool, error) { return false, notPorted("item reopen") }

// Ready is not ported.
func (b *Issues) Ready(string) ([]string, error) { return nil, notPorted("item ready") }

// Comments is not ported.
func (b *Issues) Comments(string, string) ([]Comment, error) {
	return nil, notPorted("item comment list")
}

// AddComment is not ported.
func (b *Issues) AddComment(string, string, string) (string, error) {
	return "", notPorted("item comment add")
}
