package collect

import (
	"context"
	"syscall"
)

// Storage is the used/total/percent view of one mounted path. Missing mounts
// are reported as "not mounted" rather than erroring the whole panel.
type Storage struct {
	Label   string
	Path    string
	Total   uint64
	Used    uint64
	Avail   uint64
	UsedPct float64
	Mounted bool
	Err     string
}

// storagePaths map short labels to their canonical mount paths.
var storagePaths = []struct{ Label, Path string }{
	{Label: "user", Path: "/mnt/user"},
	{Label: "cache", Path: "/mnt/cache"},
	{Label: "disk1", Path: "/mnt/disk1"},
	{Label: "disk2", Path: "/mnt/disk2"},
	{Label: "disk3", Path: "/mnt/disk3"},
}

func (c *Collector) collectStorage(ctx context.Context, d *Data) {
	out := make([]Storage, 0, len(storagePaths))
	for _, ref := range storagePaths {
		s := Storage{Label: ref.Label, Path: ref.Path}
		var st syscall.Statfs_t
		if err := syscall.Statfs(ref.Path, &st); err != nil {
			s.Err = "not mounted"
			out = append(out, s)
			continue
		}
		bsize := uint64(st.Bsize)
		s.Total = st.Blocks * bsize
		s.Used = (st.Blocks - st.Bfree) * bsize
		s.Avail = st.Bavail * bsize
		if s.Total > 0 {
			s.UsedPct = float64(s.Used) / float64(s.Total) * 100
		}
		s.Mounted = true
		out = append(out, s)
	}
	d.Storage = out
}
