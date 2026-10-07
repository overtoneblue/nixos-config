// discord-mirror — Hermes desktop half.
//
// A "Discord" page (sidebar + ⌘K) that mirrors the server the Hermes bot is in:
// categories -> channels/forums -> threads/posts. Rows bound to a Hermes session
// open it in place; turns you run here post back into the Discord thread (agent
// half). From here you can also start new forum posts / threads / channel chats
// (the gateway picks them up as yours and binds a session), and create or edit
// categories and channels of every type — forum post guidelines included, which
// become the context for every chat in that forum.
//
// Plain ESM loaded uncompiled: jsx() calls, one scoped <style>, imports limited
// to @hermes/plugin-sdk / react / react/jsx-runtime.

import {
  host,
  useQuery,
  useQueryClient,
  queryClient,
  useValue,
  ROUTES_AREA,
  SIDEBAR_NAV_AREA,
  PALETTE_AREA,
  PANES_AREA,
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle
} from '@hermes/plugin-sdk'
import { jsx, jsxs } from 'react/jsx-runtime'
import { useMemo, useState } from 'react'

const ID = 'discord-mirror'
const PATH = '/discord'
const TREE_KEY = [ID, 'tree']
const STATUS_KEY = [ID, 'status']
const PREVIEW = 8 // threads shown per channel before "show more"
const POSTABLE = new Set(['forum', 'media', 'text', 'announcement'])
const TOPIC_KINDS = new Set(['forum', 'media', 'text', 'announcement'])
const TAG_KINDS = new Set(['forum', 'media'])
const KINDS = [
  ['forum', 'Forum'],
  ['text', 'Text'],
  ['announcement', 'Announcement'],
  ['voice', 'Voice'],
  ['stage', 'Stage'],
  ['media', 'Media'],
  ['category', 'Category']
]
const GLYPH = { forum: '▤', media: '▦', text: '#', announcement: '📣', voice: '🔊', stage: '🎙', category: '▾' }

let ctxRef = null

const CSS = `
.dm-page{display:flex;flex-direction:column;height:100%;min-height:0;font-size:13px;color:var(--ui-text-secondary);position:relative}
.dm-head{display:flex;align-items:center;gap:8px;padding:10px 14px;border-bottom:1px solid var(--ui-stroke-secondary);flex-wrap:wrap}
.dm-title{font-weight:600;color:var(--ui-text-primary, inherit);font-size:14px}
.dm-sub{color:var(--ui-text-tertiary);font-size:12px}
.dm-grow{flex:1}
.dm-input,.dm-select,.dm-area{background:transparent;border:1px solid var(--ui-stroke-secondary);border-radius:6px;padding:4px 8px;color:inherit;font-size:12px;outline:none;font-family:inherit}
.dm-input:focus,.dm-select:focus,.dm-area:focus{border-color:var(--ui-accent)}
.dm-head .dm-input{width:180px}
.dm-select option{background:var(--ui-bg, #1e1e1e);color:inherit}
.dm-area{resize:vertical;min-height:90px;line-height:1.45}
.dm-btn{background:transparent;border:1px solid var(--ui-stroke-secondary);border-radius:6px;padding:3px 8px;color:var(--ui-text-tertiary);font-size:12px;cursor:pointer}
.dm-btn:hover{color:inherit;background:var(--chrome-action-hover, rgba(127,127,127,.12))}
.dm-btn.on,.dm-btn.primary{color:var(--ui-accent);border-color:var(--ui-accent)}
.dm-btn[disabled]{opacity:.5;cursor:default}
.dm-body{flex:1;min-height:0;overflow:auto;padding:6px 6px 24px}
.dm-cat{display:flex;align-items:center;gap:6px;padding:12px 8px 4px;font-size:11px;font-weight:600;letter-spacing:.04em;text-transform:uppercase;color:var(--ui-text-tertiary);cursor:pointer;user-select:none}
.dm-cat:hover{color:var(--ui-text-secondary)}
.dm-row{display:flex;align-items:center;gap:6px;padding:3px 8px;border-radius:6px;cursor:pointer;min-width:0}
.dm-row:hover{background:var(--chrome-action-hover, rgba(127,127,127,.12))}
.dm-row.sel{background:color-mix(in srgb, var(--ui-accent) 18%, transparent)}
.dm-row.nosess{color:var(--ui-text-quaternary)}
.dm-glyph{width:16px;flex:none;text-align:center;color:var(--ui-text-tertiary);font-size:12px}
.dm-name{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.dm-ch{font-weight:500}
.dm-meta{flex:none;font-size:11px;color:var(--ui-text-quaternary)}
.dm-dot{flex:none;width:6px;height:6px;border-radius:50%;background:var(--ui-accent)}
.dm-act{flex:none;font-size:12px;color:var(--ui-text-quaternary);padding:0 3px;opacity:0;border-radius:4px}
.dm-row:hover .dm-act,.dm-cat:hover .dm-act{opacity:1}
.dm-act:hover{color:var(--ui-accent)}
.dm-thread{padding-left:30px}
.dm-more{padding:2px 8px 2px 30px;font-size:11px;color:var(--ui-text-tertiary);cursor:pointer}
.dm-more:hover{color:var(--ui-accent)}
.dm-empty{padding:24px;color:var(--ui-text-tertiary)}
.dm-err{color:var(--ui-danger, #d55)}
.dm-sdot{width:7px;height:7px;border-radius:50%;display:inline-block}
.dm-modal{display:flex;flex-direction:column;gap:10px;max-height:85vh;overflow:auto;font-size:13px;color:var(--ui-text-secondary)}
.dm-page.compact .dm-head{padding:6px 8px;gap:4px}
.dm-page.compact .dm-head .dm-input{width:100%;order:9}
.dm-page.compact .dm-btn{padding:1px 6px}
.dm-page.compact .dm-body{padding:2px 2px 16px}
.dm-page.compact .dm-row{padding:3px 6px;gap:5px}
.dm-page.compact .dm-thread{padding-left:22px}
.dm-page.compact .dm-more{padding-left:22px}
.dm-page.compact .dm-cat{padding:10px 6px 3px}
.dm-field{display:flex;flex-direction:column;gap:4px}
.dm-label{font-size:11px;color:var(--ui-text-tertiary);text-transform:uppercase;letter-spacing:.04em}
.dm-hint{font-size:11px;color:var(--ui-text-quaternary)}
.dm-chips{display:flex;flex-wrap:wrap;gap:6px}
.dm-chip{border:1px solid var(--ui-stroke-secondary);border-radius:12px;padding:2px 9px;font-size:12px;cursor:pointer;color:var(--ui-text-tertiary)}
.dm-chip.on{border-color:var(--ui-accent);color:var(--ui-accent)}
.dm-foot{display:flex;justify-content:flex-end;gap:8px;align-items:center}
.dm-seg{display:flex;gap:6px}
`

// ── small helpers ───────────────────────────────────────────────────────

function rel(ts) {
  if (!ts) return ''
  const s = Math.max(0, Date.now() / 1000 - ts)
  if (s < 60) return 'now'
  if (s < 3600) return `${Math.floor(s / 60)}m`
  if (s < 86400) return `${Math.floor(s / 3600)}h`
  if (s < 86400 * 30) return `${Math.floor(s / 86400)}d`
  return `${Math.floor(s / (86400 * 30))}mo`
}

function store(key, fallback) {
  try {
    const v = ctxRef?.storage?.get(key)
    return v ?? fallback
  } catch {
    return fallback
  }
}

function save(key, value) {
  try {
    ctxRef?.storage?.set(key, value)
  } catch {}
}

function errText(e) {
  const raw = e?.body?.error || e?.data?.error || e?.message || String(e)
  const m = /"error"\s*:\s*"([^"]+)"/.exec(raw)
  return m ? m[1] : raw
}

const sleep = ms => new Promise(r => setTimeout(r, ms))

function refreshAll() {
  queryClient.invalidateQueries({ queryKey: TREE_KEY })
  queryClient.invalidateQueries({ queryKey: STATUS_KEY })
}

function openRow(node) {
  if (node.session?.id) host.openSession(node.session.id)
  else if (node.url) ctxRef?.os?.openExternal(node.url)
}

function Act({ title, onClick, children }) {
  return jsx('span', {
    className: 'dm-act',
    title,
    onClick: e => {
      e.stopPropagation()
      onClick()
    },
    children
  })
}

// ── dialogs ─────────────────────────────────────────────────────────────

// The app's own Dialog: portaled over the whole window, so it works the same
// from the full page and from the narrow sidebar tab.
function Modal({ title, onClose, children }) {
  return jsx(Dialog, {
    open: true,
    onOpenChange: open => {
      if (!open) onClose()
    },
    children: jsxs(DialogContent, {
      className: 'dm-modal',
      children: [jsx(DialogHeader, { children: jsx(DialogTitle, { children: title }) }), ...children]
    })
  })
}

function Field({ label, hint, children }) {
  return jsxs('div', {
    className: 'dm-field',
    children: [
      jsx('span', { className: 'dm-label', children: label }),
      children,
      hint ? jsx('span', { className: 'dm-hint', children: hint }) : null
    ]
  })
}

function Footer({ busy, error, label, onCancel, onSubmit, disabled }) {
  return jsxs('div', {
    className: 'dm-foot',
    children: [
      error ? jsx('span', { className: 'dm-err', style: { flex: 1, fontSize: 12 }, children: error }) : null,
      jsx('button', { type: 'button', className: 'dm-btn', onClick: onCancel, children: 'Cancel' }),
      jsx('button', {
        type: 'button',
        className: 'dm-btn primary',
        disabled: busy || disabled,
        onClick: onSubmit,
        children: busy ? '…' : label
      })
    ]
  })
}

async function openWhenBound(target, sessionId) {
  let sid = sessionId
  for (let i = 0; !sid && i < 30; i++) {
    await sleep(1000)
    try {
      sid = (await ctxRef.rest(`/session?target=${encodeURIComponent(target)}`))?.session_id
    } catch {}
  }
  refreshAll()
  if (sid) host.openSession(sid)
  else host.notify({ kind: 'warning', message: 'Post created, but no Hermes session appeared yet — it will show up in the tree.' })
}

function NewPostDialog({ channel, onClose }) {
  const isForum = channel.kind === 'forum' || channel.kind === 'media'
  const [title, setTitle] = useState('')
  const [content, setContent] = useState('')
  const [tags, setTags] = useState([])
  const [mode, setMode] = useState('thread')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const submit = async () => {
    setBusy(true)
    setError('')
    try {
      const res = await ctxRef.rest('/posts', {
        method: 'POST',
        body: { channel_id: channel.id, title, content, tags, mode: isForum ? 'thread' : mode },
        timeoutMs: 60000
      })
      onClose()
      if (res?.dispatched) {
        host.notify({ kind: 'info', message: `Posted in #${channel.name} — Nolan is on it.` })
        openWhenBound(res.target, res.session_id)
      } else {
        refreshAll()
        host.notify({
          kind: 'warning',
          message: `Posted in #${channel.name}, but the agent didn't pick it up: ${res?.dispatch_error || 'unknown'}`
        })
      }
    } catch (e) {
      setError(errText(e))
      setBusy(false)
    }
  }
  const kids = []
  if (!isForum)
    kids.push(
      jsx(Field, {
        label: 'Where',
        children: jsx('div', {
          className: 'dm-seg',
          children: [
            ['thread', 'New thread'],
            ['channel', `In #${channel.name}`]
          ].map(([k, l]) =>
            jsx('span', { className: `dm-chip${mode === k ? ' on' : ''}`, onClick: () => setMode(k), children: l }, k)
          )
        })
      })
    )
  if (isForum || mode === 'thread')
    kids.push(
      jsx(Field, {
        label: isForum ? 'Post title' : 'Thread name',
        hint: 'Optional — defaults to the first line of your message.',
        children: jsx('input', {
          className: 'dm-input',
          value: title,
          maxLength: 100,
          onChange: e => setTitle(e.target.value),
          autoFocus: true
        })
      })
    )
  kids.push(
    jsx(Field, {
      label: 'Message',
      hint: 'Posted as you; Nolan answers in the thread and here.',
      children: jsx('textarea', {
        className: 'dm-area',
        rows: 7,
        value: content,
        onChange: e => setContent(e.target.value),
        onKeyDown: e => {
          if (e.key === 'Enter' && (e.metaKey || e.ctrlKey) && content.trim()) submit()
        }
      })
    })
  )
  if (isForum && channel.tags?.length)
    kids.push(
      jsx(Field, {
        label: 'Tags',
        children: jsx('div', {
          className: 'dm-chips',
          children: channel.tags.map(t =>
            jsx(
              'span',
              {
                className: `dm-chip${tags.includes(t.id) ? ' on' : ''}`,
                onClick: () =>
                  setTags(cur =>
                    cur.includes(t.id) ? cur.filter(x => x !== t.id) : cur.length < 5 ? [...cur, t.id] : cur
                  ),
                children: `${t.emoji ? t.emoji + ' ' : ''}${t.name}`
              },
              t.id
            )
          )
        })
      })
    )
  if (isForum && channel.topic)
    kids.push(jsx(Field, { label: 'Post guidelines (context for this chat)', children: jsx('div', { className: 'dm-hint', style: { whiteSpace: 'pre-wrap' }, children: channel.topic }) }))
  kids.push(jsx(Footer, { busy, error, label: isForum ? 'Create post' : mode === 'thread' ? 'Start thread' : 'Send', onCancel: onClose, onSubmit: submit, disabled: !content.trim() }))
  return jsx(Modal, { title: isForum ? `New post in ${channel.name}` : `New conversation in #${channel.name}`, onClose, children: kids })
}

function ChannelDialog({ dlg, categories, onClose }) {
  const editing = dlg.mode === 'edit'
  const node = dlg.node || {}
  const [kind, setKind] = useState(editing ? node.kind : dlg.kind || 'forum')
  const [name, setName] = useState(editing ? node.name : '')
  const [topic, setTopic] = useState(editing ? node.topic || '' : '')
  const [tags, setTags] = useState(editing ? (node.tags || []).map(t => t.name).join(', ') : '')
  const [layout, setLayout] = useState('list')
  const [parent, setParent] = useState(editing ? node.parent_id || '' : dlg.parent_id || '')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const isForum = kind === 'forum' || kind === 'media'
  const submit = async () => {
    setBusy(true)
    setError('')
    try {
      const tagList = tags.split(',').map(s => s.trim()).filter(Boolean)
      if (editing) {
        const body = { name }
        if (TOPIC_KINDS.has(kind)) body.topic = topic
        if (TAG_KINDS.has(kind)) body.tags = tagList
        if (kind !== 'category' && (parent || null) !== (node.parent_id || null)) body.parent_id = parent || null
        await ctxRef.rest(`/channels/${node.id}`, { method: 'PATCH', body })
      } else {
        const body = { guild_id: dlg.guild_id, kind, name }
        if (kind !== 'category' && parent) body.parent_id = parent
        if (TOPIC_KINDS.has(kind) && topic.trim()) body.topic = topic
        if (TAG_KINDS.has(kind) && tagList.length) body.tags = tagList
        if (kind === 'forum') body.layout = layout
        await ctxRef.rest('/channels', { method: 'POST', body })
      }
      onClose()
      refreshAll()
      host.notify({ kind: 'info', message: editing ? `Updated ${name}` : `Created ${kind} ${name}` })
    } catch (e) {
      setError(errText(e))
      setBusy(false)
    }
  }
  const kids = []
  if (!editing)
    kids.push(
      jsx(Field, {
        label: 'Type',
        children: jsx('div', {
          className: 'dm-chips',
          children: KINDS.filter(([k]) => !(dlg.parent_id && k === 'category')).map(([k, l]) =>
            jsx('span', { className: `dm-chip${kind === k ? ' on' : ''}`, onClick: () => setKind(k), children: `${GLYPH[k]} ${l}` }, k)
          )
        })
      })
    )
  kids.push(
    jsx(Field, {
      label: 'Name',
      children: jsx('input', { className: 'dm-input', value: name, maxLength: 100, autoFocus: true, onChange: e => setName(e.target.value) })
    })
  )
  if (kind !== 'category')
    kids.push(
      jsx(Field, {
        label: 'Category',
        children: jsx('select', {
          className: 'dm-select',
          value: parent,
          onChange: e => setParent(e.target.value),
          children: [jsx('option', { value: '', children: '— none —' }, ''), ...categories.map(c => jsx('option', { value: c.id, children: c.name }, c.id))]
        })
      })
    )
  if (TOPIC_KINDS.has(kind))
    kids.push(
      jsx(Field, {
        label: isForum ? 'Post guidelines' : 'Topic',
        hint: isForum
          ? 'Shown on every post and handed to Nolan as context for each chat in this forum (up to 4096 chars).'
          : 'Channel topic — also passed to Nolan as context (up to 1024 chars).',
        children: jsx('textarea', { className: 'dm-area', rows: isForum ? 8 : 4, value: topic, maxLength: isForum ? 4096 : 1024, onChange: e => setTopic(e.target.value) })
      })
    )
  if (TAG_KINDS.has(kind))
    kids.push(
      jsx(Field, {
        label: 'Tags',
        hint: 'Comma-separated, up to 20.',
        children: jsx('input', { className: 'dm-input', value: tags, onChange: e => setTags(e.target.value) })
      })
    )
  if (!editing && kind === 'forum')
    kids.push(
      jsx(Field, {
        label: 'Default layout',
        children: jsx('div', {
          className: 'dm-seg',
          children: ['list', 'gallery'].map(l => jsx('span', { className: `dm-chip${layout === l ? ' on' : ''}`, onClick: () => setLayout(l), children: l }, l))
        })
      })
    )
  if (!editing && (kind === 'announcement' || kind === 'stage' || kind === 'media'))
    kids.push(jsx('span', { className: 'dm-hint', children: 'Needs a Community-enabled server; Discord will refuse it otherwise.' }))
  kids.push(jsx(Footer, { busy, error, label: editing ? 'Save' : 'Create', onCancel: onClose, onSubmit: submit, disabled: !name.trim() }))
  return jsx(Modal, { title: editing ? `Edit ${node.name}` : dlg.parent_name ? `New channel in ${dlg.parent_name}` : 'New channel', onClose, children: kids })
}

// ── tree ────────────────────────────────────────────────────────────────

function ThreadRow({ t, focused }) {
  const has = !!t.session
  return jsxs('div', {
    className: `dm-row dm-thread${has ? '' : ' nosess'}${has && t.session.id === focused ? ' sel' : ''}`,
    title: has ? `${t.name}\nHermes: ${t.session.title || t.session.id}` : `${t.name}\nNo Hermes session yet — opens in Discord`,
    onClick: () => openRow(t),
    children: [
      jsx('span', { className: 'dm-glyph', children: t.archived ? '·' : '›' }),
      jsx('span', { className: 'dm-name', children: t.name }),
      has ? jsx('span', { className: 'dm-dot', title: 'Hermes session' }) : null,
      jsx('span', { className: 'dm-meta', children: rel(t.last_active) }),
      jsx(Act, { title: 'Open in Discord', onClick: () => ctxRef?.os?.openExternal(t.url), children: '↗' })
    ]
  })
}

function ChannelBlock({ ch, focused, filter, showArchived, expanded, setExpanded, setDialog }) {
  const q = filter.trim().toLowerCase()
  const chMatch = !q || ch.name.toLowerCase().includes(q)
  let threads = ch.threads.filter(t => showArchived || !t.archived || (t.session && t.session.id === focused))
  if (q && !chMatch) threads = threads.filter(t => t.name.toLowerCase().includes(q))
  if (q && !chMatch && threads.length === 0) return null
  const open = expanded[ch.id] || !!q
  const shown = open ? threads : threads.slice(0, PREVIEW)
  const hidden = threads.length - shown.length
  const has = !!ch.session
  const postable = POSTABLE.has(ch.kind)
  return jsxs('div', {
    children: [
      jsxs('div', {
        className: `dm-row${has && ch.session.id === focused ? ' sel' : ''}`,
        title: ch.topic || ch.name,
        onClick: () => (has || !postable ? openRow(ch) : setDialog({ type: 'post', channel: ch })),
        children: [
          jsx('span', { className: 'dm-glyph', children: GLYPH[ch.kind] || '#' }),
          jsx('span', { className: 'dm-name dm-ch', children: ch.name }),
          has ? jsx('span', { className: 'dm-dot', title: 'Hermes session' }) : null,
          jsx('span', { className: 'dm-meta', children: threads.length ? `${threads.length}` : '' }),
          postable
            ? jsx(Act, {
                title: ch.kind === 'forum' || ch.kind === 'media' ? 'New post' : 'New thread / message',
                onClick: () => setDialog({ type: 'post', channel: ch }),
                children: '+'
              })
            : null,
          jsx(Act, { title: 'Edit channel', onClick: () => setDialog({ type: 'channel', mode: 'edit', node: ch }), children: '✎' }),
          jsx(Act, { title: 'Open in Discord', onClick: () => ctxRef?.os?.openExternal(ch.url), children: '↗' })
        ]
      }),
      ...shown.map(t => jsx(ThreadRow, { t, focused }, t.id)),
      hidden > 0
        ? jsx('div', { className: 'dm-more', onClick: () => setExpanded(ch.id, true), children: `show ${hidden} more` })
        : open && !q && threads.length > PREVIEW
          ? jsx('div', { className: 'dm-more', onClick: () => setExpanded(ch.id, false), children: 'show less' })
          : null
    ]
  })
}

function StatusChip({ status }) {
  if (!status) return null
  const err = status.last_error
  const recentErr = err && (!status.last_ok || err.at > status.last_ok.at)
  const color = !status.ok ? 'var(--ui-danger, #d55)' : recentErr || !status.bridge ? '#d9a33a' : 'var(--ui-accent)'
  const label = !status.ok ? 'mirror off' : recentErr ? 'mirror error' : !status.bridge ? 'two-way · no new posts' : 'two-way'
  const tip = recentErr
    ? `Last mirror error: ${err.error}`
    : !status.bridge
      ? 'Replies mirror both ways, but the gateway bridge is down: new posts from here will not be picked up (restart hermes-agent).'
      : 'Desktop turns in Discord-bound sessions post back to Discord; new posts start gateway sessions.'
  return jsxs('span', {
    className: 'dm-sub',
    title: tip,
    style: { display: 'inline-flex', alignItems: 'center', gap: 5 },
    children: [jsx('span', { className: 'dm-sdot', style: { background: color } }), label]
  })
}

function DiscordView({ compact = false }) {
  const qc = useQueryClient()
  const focused = useValue(host.state.focusedStoredSessionId)
  const [filter, setFilter] = useState('')
  const [collapsed, setCollapsed] = useState(() => store('collapsed', {}))
  const [expanded, setExpandedState] = useState({})
  const [showArchived, setShowArchived] = useState(() => store('showArchived', false))
  const [busy, setBusy] = useState(false)
  const [dialog, setDialog] = useState(null)

  const tree = useQuery({ queryKey: TREE_KEY, queryFn: () => ctxRef.rest('/tree'), refetchInterval: 30000, staleTime: 10000 })
  const status = useQuery({ queryKey: STATUS_KEY, queryFn: () => ctxRef.rest('/status'), refetchInterval: 30000 })

  const toggleCat = id =>
    setCollapsed(c => {
      const next = { ...c, [id]: !c[id] }
      save('collapsed', next)
      return next
    })
  const setExpanded = (id, v) => setExpandedState(e => ({ ...e, [id]: v }))
  const refresh = async () => {
    setBusy(true)
    try {
      await ctxRef.rest('/tree?refresh=true')
    } catch {}
    await qc.invalidateQueries({ queryKey: TREE_KEY })
    await qc.invalidateQueries({ queryKey: STATUS_KEY })
    setBusy(false)
  }

  const data = tree.data
  const guilds = data?.guilds || []
  const guild = guilds[0]
  const q = filter.trim()
  const categories = (guild?.categories || []).filter(c => c.id).map(c => ({ id: c.id, name: c.name }))

  const body = useMemo(() => {
    if (tree.isLoading) return jsx('div', { className: 'dm-empty', children: 'Loading Discord…' })
    if (tree.error) return jsx('div', { className: 'dm-empty dm-err', children: `Backend unreachable: ${errText(tree.error)}` })
    if (data && data.ok === false) return jsx('div', { className: 'dm-empty dm-err', children: data.error })
    if (!guilds.length) return jsx('div', { className: 'dm-empty', children: 'The bot is not in any server.' })
    return guilds.map(g =>
      jsxs(
        'div',
        {
          children: [
            guilds.length > 1 ? jsx('div', { className: 'dm-cat', children: g.name }) : null,
            ...g.categories.map(cat => {
              const key = cat.id || 'none'
              const isCollapsed = !q && collapsed[key]
              const blocks = isCollapsed
                ? []
                : cat.channels.map(ch =>
                    jsx(ChannelBlock, { ch, focused, filter, showArchived, expanded, setExpanded, setDialog }, ch.id)
                  )
              return jsxs(
                'div',
                {
                  children: [
                    cat.name
                      ? jsxs('div', {
                          className: 'dm-cat',
                          onClick: () => toggleCat(key),
                          children: [
                            jsx('span', { children: isCollapsed ? '▸' : '▾' }),
                            jsx('span', { style: { flex: 1 }, children: cat.name }),
                            jsx(Act, {
                              title: 'New channel in this category',
                              onClick: () => setDialog({ type: 'channel', mode: 'create', guild_id: g.id, parent_id: cat.id, parent_name: cat.name }),
                              children: '+'
                            }),
                            jsx(Act, {
                              title: 'Rename category',
                              onClick: () => setDialog({ type: 'channel', mode: 'edit', node: { ...cat, kind: 'category' } }),
                              children: '✎'
                            })
                          ]
                        })
                      : null,
                    ...blocks
                  ]
                },
                key
              )
            })
          ]
        },
        g.id
      )
    )
  }, [tree.isLoading, tree.error, data, collapsed, expanded, filter, showArchived, focused])

  const close = () => setDialog(null)
  const btn = (full, short, props) =>
    jsx('button', { type: 'button', className: 'dm-btn', ...props, children: compact ? short : full })
  return jsxs('div', {
    className: `dm-page${compact ? ' compact' : ''}`,
    children: [
      jsx('style', { children: CSS }),
      jsxs('div', {
        className: 'dm-head',
        children: [
          compact ? null : jsx('span', { className: 'dm-title', children: 'Discord' }),
          compact ? null : jsx('span', { className: 'dm-sub', children: guilds.length === 1 ? guilds[0].name : '' }),
          jsx(StatusChip, { status: status.data }),
          jsx('span', { className: 'dm-grow' }),
          jsx('input', { className: 'dm-input', placeholder: compact ? 'Filter' : 'Filter channels & posts', value: filter, onChange: e => setFilter(e.target.value) }),
          guild
            ? btn('+ channel', '+ ch', {
                title: 'Create a channel (any type) or a category',
                onClick: () => setDialog({ type: 'channel', mode: 'create', guild_id: guild.id })
              })
            : null,
          guild
            ? btn('+ category', '+ cat', {
                title: 'Create a category',
                onClick: () => setDialog({ type: 'channel', mode: 'create', guild_id: guild.id, kind: 'category' })
              })
            : null,
          jsx('button', {
            type: 'button',
            className: `dm-btn${showArchived ? ' on' : ''}`,
            title: 'Show archived threads/posts',
            onClick: () => {
              save('showArchived', !showArchived)
              setShowArchived(!showArchived)
            },
            children: compact ? 'arch' : 'archived'
          }),
          btn(busy ? '…' : 'refresh', busy ? '…' : '↻', { title: 'Re-fetch the server from Discord', onClick: refresh })
        ]
      }),
      jsx('div', { className: 'dm-body', children: body }),
      dialog?.type === 'post' ? jsx(NewPostDialog, { channel: dialog.channel, onClose: close }) : null,
      dialog?.type === 'channel' ? jsx(ChannelDialog, { dlg: dialog, categories, onClose: close }) : null
    ]
  })
}

export default {
  id: ID,
  name: 'Discord mirror',
  register(ctx) {
    ctxRef = ctx
    ctx.registerMany([
      { id: 'page', area: ROUTES_AREA, data: { path: PATH }, render: () => jsx(DiscordView, {}) },
      // Sidebar tab next to Sessions (same recipe as Bot Mode's Bots tab).
      // hideOnly: closing the tab hides it instead of disabling the plugin.
      {
        id: 'pane',
        area: PANES_AREA,
        title: 'Discord',
        data: {
          placement: 'left',
          width: '260px',
          collapsible: true,
          hideOnly: true,
          tabTitleText: () => 'Discord',
          dock: { pane: 'sessions', pos: 'center', enforce: true }
        },
        render: () => jsx(DiscordView, { compact: true })
      },
      { id: 'nav', area: SIDEBAR_NAV_AREA, data: { path: PATH, label: 'Discord', codicon: 'comment-discussion' } },
      {
        id: 'open',
        area: PALETTE_AREA,
        data: {
          id: 'discord-mirror.open',
          label: 'Discord: open server mirror',
          keywords: ['discord', 'server', 'channels', 'forum', 'threads', 'post'],
          run: () => host.navigate(PATH)
        }
      }
    ])
    // A desktop turn just landed in Discord: refresh the tree's activity.
    ctx.onEvent(`plugin.${ID}.mirrored`, refreshAll)
    ctx.onEvent(`plugin.${ID}.error`, ev => {
      queryClient.invalidateQueries({ queryKey: STATUS_KEY })
      host.notify({ kind: 'error', message: `Discord mirror: ${ev?.payload?.error || 'post failed'}` })
    })
  }
}
