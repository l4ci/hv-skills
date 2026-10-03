package cli

// The round group: the orchestrator layer over the worker registry and host
// package. One Subs line per verb, so verbs landing from separate branches
// append without touching each other's lines.
func roundCommands() *Command {
	return &Command{Name: "round", Summary: "orchestrator view of a round's workers", Subs: []*Command{
		{Name: "wait", Summary: "block until a worker needs attention", Verb: roundWait},
		{Name: "status", Summary: "list the round's slots with host, PR and drift", Verb: roundStatus},
		{Name: "reconcile", Summary: "report drift between registry, host, git and forge; --apply repairs the safe kinds", Verb: roundReconcile},
		roundEscalate(),
	}}
}
