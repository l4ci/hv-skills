package escalation

import (
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/tracker"
)

// markerPrefix opens every comment marker hv writes. A comment carrying it is
// hv's own and never an answer.
const markerPrefix = "<!-- hv:"

// IsAnswer is the answer rule for one comment body: any comment without an hv
// marker. The author decides nothing, because the orchestrator and the human
// usually post as the same account; hv marks every comment it posts instead.
// To change what counts as an answer, change this function; everything else
// goes through it.
func IsAnswer(body string) bool {
	return !strings.Contains(body, markerPrefix)
}

// FindAnswer applies the rule to a thread's comments, oldest first: the answer
// is the first comment after the escalation comment for which IsAnswer holds.
// escFound is false when the escalation comment is not in the list (deleted),
// in which case nothing can be ordered against it and found is false too.
func FindAnswer(comments []tracker.Comment, escalationCommentID string) (answer tracker.Comment, found, escFound bool) {
	for _, c := range comments {
		if !escFound {
			escFound = c.ID == escalationCommentID
			continue
		}
		if IsAnswer(c.Body) {
			return c, true, true
		}
	}
	return tracker.Comment{}, false, escFound
}
