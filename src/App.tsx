import { useEffect, useRef, useState } from 'react'
import type { ChangeEvent, KeyboardEvent, ReactNode } from 'react'
import './App.css'

type Token = { name: string; value: string; type: string; source: string }
type Repo = { id: string; name: string; description: string; tokens: Token[]; demo?: boolean }
const initialTokens: Token[] = [
  ['--background-default', '#FFFFFF', 'Color'], ['--background-subtle', '#F8FAFC', 'Color'], ['--background-muted', '#F1F5F9', 'Color'],
  ['--foreground-default', '#0F172A', 'Color'], ['--foreground-muted', '#64748B', 'Color'], ['--foreground-subtle', '#94A3B8', 'Color'],
  ['--border-default', '#E2E8F0', 'Color'], ['--border-strong', '#CBD5E1', 'Color'], ['--border-focus', '#6366F1', 'Color'],
  ['--accent-default', '#6366F1', 'Color'], ['--accent-hover', '#4F46E5', 'Color'], ['--accent-subtle', '#EEF2FF', 'Color'],
  ['--radius-sm', '4px', 'Radius'], ['--radius-md', '8px', 'Radius'], ['--radius-lg', '12px', 'Radius'],
  ['--spacing-xs', '4px', 'Spacing'], ['--spacing-sm', '8px', 'Spacing'], ['--spacing-md', '16px', 'Spacing'], ['--spacing-lg', '24px', 'Spacing'],
  ['--font-body', 'Inter, sans-serif', 'Typography'], ['--font-size-sm', '14px', 'Typography'], ['--font-size-base', '16px', 'Typography'],
  ['.button-primary', 'Component class', 'Class'], ['.card', 'Component class', 'Class'],
].map(([name, value, type]) => ({ name, value, type, source: type === 'Class' ? 'src/styles/components.css' : 'src/styles/tokens.css' }))
const demoRepo: Repo = { id: 'acme-web', name: 'acme-web', description: 'Your product, speaking the same language.', tokens: initialTokens, demo: true }
const categories = ['All tokens', 'Color', 'Typography', 'Spacing', 'Radius', 'Class']
function Icon({ name, size = 18, ...props }: { name: string; size?: number; className?: string }) {
  const paths: Record<string, ReactNode> = {
    grid: <><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></>,
    code: <><path d="m8 7-5 5 5 5m8-10 5 5-5 5m-3-13-2 21"/></>,
    cube: <><path d="m12 3 9 5v8l-9 5-9-5V8l9-5ZM3 8l9 5 9-5M12 13v8M7.5 5.5l9 5"/></>,
    plus: <path d="M12 5v14M5 12h14"/>, search: <><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4.5 4.5"/></>,
    chevron: <path d="m9 5 7 7-7 7"/>, down: <path d="m7 10 5 5 5-5"/>, arrow: <path d="M12 19V5m-6 6 6-6 6 6"/>,
    branch: <><circle cx="6" cy="5" r="2"/><circle cx="6" cy="19" r="2"/><circle cx="18" cy="5" r="2"/><path d="M6 7v10m12-10c0 6-12 4-12 9"/></>,
    book: <><path d="M12 5v16M3 4c4-1 7-1 9 1 2-2 5-2 9-1v15c-4-1-7-1-9 1-2-2-5-2-9-1V4Z"/></>,
    settings: <><circle cx="12" cy="12" r="4"/><path d="m9 3-1 3-3 1-2 3 2 2-1 3 3 2 2 4 3-1 3 1 2-4 3-2-1-3 2-2-2-3-3-1-1-3H9Z"/></>,
    help: <><circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 1 1 4 2c-1 .7-1.5 1-1.5 3m0 2v1"/></>,
    sparkle: <><path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3Z"/></>,
    sync: <><path d="M20 8a8 8 0 0 0-14-2L3 9m0-6v6h6m-5 7a8 8 0 0 0 14 2l3-3m0 6v-6h-6"/></>,
    check: <path d="m5 12 4 4L19 6"/>, close: <path d="m6 6 12 12M6 18 18 6"/>, folder: <path d="M3 6a2 2 0 0 1 2-2h5l2 3h7a2 2 0 0 1 2 2v10H3V6Z"/>,
    link: <><path d="m10 13 4-4m-6 6-1 1a4 4 0 0 1-6-6l4-4a4 4 0 0 1 6 0m2 2 1-1a4 4 0 0 1 6 6l-4 4a4 4 0 0 1-6 0"/></>,
    clock: <><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></>, external: <><path d="M14 3h7v7m0-7L10 14M10 4H4v16h16v-6"/></>,
  }
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...props}>{paths[name] || paths.code}</svg>
}
function TokenMark({ token }: { token: Token }) {
  return token.type === 'Color' ? <span className="swatch" style={{ background: /^(#|rgb|hsl|oklch|transparent|white|black)/.test(token.value) ? token.value : '#e5e7eb' }}/> : <span className={`type-mark type-${token.type.toLowerCase()}`}>{token.type === 'Typography' ? 'Aa' : token.type === 'Radius' ? '⌜' : token.type === 'Spacing' ? '↔' : '⌘'}</span>
}
function parseFiles(files: { name: string; text: string }[]): Token[] {
  const tokens = new Map<string, Token>()
  files.forEach(file => {
    for (const match of file.text.matchAll(/(--[\w-]+)\s*:\s*([^;{}\n]+)/g)) {
      const [, name, raw] = match; const value = raw.trim()
      const type = /color|background|foreground|border|accent|surface|fill|stroke/.test(name) && !/width|radius/.test(name) || /^(#|rgb|hsl|oklch)/.test(value) ? 'Color' : /radius/.test(name) ? 'Radius' : /font|line-height|letter/.test(name) ? 'Typography' : 'Spacing'
      tokens.set(name, { name, value, type, source: file.name })
    }
    for (const match of file.text.matchAll(/\.([a-zA-Z_][\w-]*)\s*(?:[,:][^{}]*)?\{/g)) {
      const name = `.${match[1]}`; tokens.set(name, { name, value: 'CSS class', type: 'Class', source: file.name })
    }
  })
  return [...tokens.values()]
}
function App() {
  const [repos, setRepos] = useState<Repo[]>(() => { try { const saved = localStorage.getItem('semantic-repos'); return saved ? JSON.parse(saved) : [demoRepo] } catch { return [demoRepo] } })
  const [repoId, setRepoId] = useState(repos[0]?.id || '')
  const [view, setView] = useState('workspace')
  const [category, setCategory] = useState('All tokens')
  const [search, setSearch] = useState('')
  const [prompt, setPrompt] = useState('')
  const [cursor, setCursor] = useState(0)
  const [dismissed, setDismissed] = useState(false)
  const [selected, setSelected] = useState(0)
  const [modal, setModal] = useState<string | null>(null)
  const [notice, setNotice] = useState('')
  const [fileError, setFileError] = useState('')
  const [loading, setLoading] = useState(false)
  const [output, setOutput] = useState('')
  const [detail, setDetail] = useState<Token | null>(null)
  const input = useRef<HTMLTextAreaElement>(null)
  const folderInput = useRef<HTMLInputElement>(null)
  const repo = repos.find(r => r.id === repoId) || repos[0]
  const tokens = repo?.tokens || []
  const visible = tokens.filter(t => (category === 'All tokens' || t.type === category) && `${t.name} ${t.value}`.toLowerCase().includes(search.toLowerCase()))
  const mention = prompt.slice(0, cursor).match(/(?:^|\s)#([^\s#]*)$/)
  const options = mention && !dismissed ? tokens.filter(t => t.name.toLowerCase().includes(mention[1].toLowerCase())) : []
  const isOpen = !!mention && !dismissed
  useEffect(() => { localStorage.setItem('semantic-repos', JSON.stringify(repos)) }, [repos])
  useEffect(() => { if (notice) { const timer = setTimeout(() => setNotice(''), 3500); return () => clearTimeout(timer) } }, [notice])
  useEffect(() => { document.getElementById(`mention-${selected}`)?.scrollIntoView({ block: 'nearest' }) }, [selected])
  useEffect(() => {
    const closeOnEscape = (event: globalThis.KeyboardEvent) => { if (event.key === 'Escape') { setModal(null); setDetail(null) } }
    window.addEventListener('keydown', closeOnEscape)
    return () => window.removeEventListener('keydown', closeOnEscape)
  }, [])
  const insertToken = (token: Token) => {
    const before = prompt.slice(0, cursor)
    const start = mention ? before.lastIndexOf('#') : cursor
    const insertion = `${mention || !before || /\s$/.test(before) ? '' : ' '}#${token.name} `
    setPrompt(prompt.slice(0, start) + insertion + prompt.slice(cursor)); setDismissed(true)
    requestAnimationFrame(() => { input.current?.focus(); input.current?.setSelectionRange(start + insertion.length, start + insertion.length); setCursor(start + insertion.length) })
  }
  const onKey = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (isOpen) {
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') { event.preventDefault(); setSelected(s => options.length ? (s + (event.key === 'ArrowDown' ? 1 : -1) + options.length) % options.length : 0) }
      if ((event.key === 'Enter' || event.key === 'Tab') && options.length) { event.preventDefault(); insertToken(options[Math.min(selected, options.length - 1)]) }
      if (event.key === 'Escape') { event.preventDefault(); setDismissed(true) }
    } else if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) { event.preventDefault(); preparePrompt() }
  }
  const preparePrompt = () => {
    if (!prompt.trim()) return
    const mentionedNames = new Set(Array.from(prompt.matchAll(/#([.\w-]+)/g), match => match[1]))
    const references = tokens.filter(t => mentionedNames.has(t.name))
    setOutput(`${prompt.trim()}\n\nCodebase: ${repo?.name || 'None'}${references.length ? '\n\nDesign system references:\n' + references.map(t => `${t.name}: ${t.value}\nSource: ${t.source}\nUsage: ${t.type === 'Class' ? t.name : `var(${t.name})`}`).join('\n\n') : ''}`)
    setModal('output')
  }
  const connect = async (event: ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(event.target.files || []); if (!files.length) return
    setLoading(true); setFileError('')
    try {
      const styles = files.filter(f => /\.(css|scss|sass|less)$/.test(f.name) && !/(^|\/)(node_modules|dist|build|\.git)\//.test(f.webkitRelativePath) && f.size < 2_000_000)
      const extracted = parseFiles(await Promise.all(styles.map(async f => ({ name: (f.webkitRelativePath || f.name).split('/').slice(1).join('/') || f.name, text: await f.text() }))))
      if (!extracted.length) { setFileError('No CSS variables or classes found. Choose a folder containing CSS, SCSS, Sass, or Less files.'); return }
      const name = files[0].webkitRelativePath.split('/')[0] || 'Local codebase'
      const id = `local-${name}`
      setRepos(prev => [...prev.filter(r => r.id !== id), { id, name, description: 'Connected from a local folder', tokens: extracted }]); setRepoId(id); setCategory('All tokens'); setSearch(''); setModal(null); setNotice(`Connected ${name} · ${extracted.length} tokens found`)
    } catch { setFileError('Could not read this folder. Try selecting it again.') } finally { setLoading(false); event.target.value = '' }
  }
  const copy = async (text: string) => { try { await navigator.clipboard.writeText(text); setNotice('Copied to clipboard') } catch { setNotice('Clipboard unavailable. Select and copy the text manually.') } }
  return <div className="app-shell">
    <aside className="sidebar">
      <a className="brand" href="#" onClick={e => { e.preventDefault(); setView('workspace') }}><span className="brand-symbol">#<span>·</span></span>DesignSnippets<span className="beta">BETA</span></a>
      <button className="workspace-switch" onClick={() => setModal('workspace')}><span className="workspace-avatar">S</span><span>Studio workspace<small>Personal workspace</small></span><Icon name="down" size={15}/></button>
      <div className="nav-caption">WORKSPACE</div>
      <nav><button className={view === 'workspace' ? 'nav-item active' : 'nav-item'} onClick={() => setView('workspace')}><Icon name="grid"/>Overview</button><button className={view === 'codebases' ? 'nav-item active' : 'nav-item'} onClick={() => setView('codebases')}><Icon name="code"/>Codebases<span className="nav-count">{repos.length}</span></button><button className={view === 'library' ? 'nav-item active' : 'nav-item'} onClick={() => setView('library')}><Icon name="cube"/>Token library</button></nav>
      <div className="nav-caption codebase-caption">CONNECTED CODEBASES<button aria-label="Connect a codebase" onClick={() => { setFileError(''); setModal('connect') }}><Icon name="plus" size={14}/></button></div>
      {repos.map(r => <button key={r.id} className={`repo-nav ${repo?.id === r.id ? 'selected' : ''}`} onClick={() => { setRepoId(r.id); setCategory('All tokens'); setSearch(''); setView('workspace') }}><span className="status-dot"/>{r.name}<Icon name="chevron" size={13}/></button>)}
      <div className="sidebar-bottom"><div className="sidebar-tip"><span className="tip-icon">#</span><strong>A little context. A lot of clarity.</strong><p>Your design system, right where<br/>your next idea starts.</p><button onClick={() => setModal('help')}>See how it works <span>↗</span></button></div><button className="nav-item" onClick={() => setModal('help')}><Icon name="book"/>Documentation<Icon name="external" size={13}/></button><button className="nav-item" onClick={() => setModal('settings')}><Icon name="settings"/>Settings</button><div className="profile"><span className="user-avatar">JD</span><div>Jamie Davis<small>Personal account</small></div><button aria-label="Account information" onClick={() => setModal('workspace')}><Icon name="down" size={15}/></button></div></div>
    </aside>
    <div className="main-shell"><header className="topbar"><div>Workspace<Icon name="chevron" size={13}/><span>{view === 'library' ? 'Token library' : view === 'codebases' ? 'Codebases' : 'Overview'}</span></div><button onClick={() => setModal('help')}><Icon name="help" size={17}/> Help & feedback <span>↗</span></button></header>
    <main>
      <div className="page-heading"><div><div className="eyebrow"><span/> A SHARED LANGUAGE FOR YOU AND YOUR AGENT</div><h1>{view === 'library' ? 'Your design vocabulary.' : view === 'codebases' ? 'Great work starts connected.' : 'Less guessing. More building.'}</h1><p>Connect your codebase. Reference your tokens. Keep every detail in sync.</p></div><button className="button connect-button" onClick={() => { setFileError(''); setModal('connect') }}><Icon name="plus" size={16}/> Connect codebase</button></div>
      <div className="section-label">YOUR CODEBASES <span>{repos.length.toString().padStart(2, '0')}</span></div>
      <div className="repo-grid">{repos.map(r => <button key={r.id} className={`repo-card ${repo?.id === r.id ? 'current' : ''}`} onClick={() => { setRepoId(r.id); setCategory('All tokens'); setSearch('') }}><div className="repo-card-top"><span className="repo-icon"><Icon name="code" size={20}/></span><span className="connected"><span className="status-dot"/>{r.demo ? 'Example codebase' : 'Connected'}</span><Icon name="chevron" size={16}/></div><h3>{r.name}<span>{r.demo ? 'Demo' : 'Local'}</span></h3><p>{r.demo ? 'acme / acme-web' : r.description}</p><div className="repo-card-footer"><span><Icon name="cube" size={14}/>{r.tokens.length} tokens</span><span><Icon name="branch" size={13}/>{r.demo ? 'main' : 'local'}</span><span className="repo-sync"><span className="status-dot"/>{r.demo ? 'Ready to explore' : 'Imported'}</span></div></button>)}<button className="add-repo-card" onClick={() => { setFileError(''); setModal('connect') }}><span><Icon name="plus" size={21}/></span><strong>Bring your codebase</strong><p>Good design starts with a connection.</p><span className="add-repo-link">Connect a codebase <span>↗</span></span></button></div>
      {view !== 'codebases' && <>
      <section className="playground"><div className="section-title"><div><span className="square-icon"><Icon name="sparkle" size={18}/></span><h2>Give your agent the right context</h2></div><span className="pill">PLAYGROUND</span></div><p className="section-description">Speak naturally. Type <kbd>#</kbd> to bring your design system into the conversation.</p>
      <div className={`composer ${isOpen ? 'has-menu' : ''}`}>
      <div className="composer-context"><span className="context-dot"/><select aria-label="Prompt codebase" value={repo?.id || ''} onChange={e => { setRepoId(e.target.value); setSelected(0) }}>{repos.map(r => <option key={r.id} value={r.id}>{r.name}</option>)}</select><span>/</span><Icon name="cube" size={13}/><span>Design system</span></div>
      <textarea ref={input} value={prompt} placeholder="Update the card border to #--border-default…" aria-label="Message your agent" aria-autocomplete="list" aria-controls={isOpen ? 'token-options' : undefined} aria-activedescendant={isOpen && options.length ? `mention-${selected}` : undefined} onChange={e => { setPrompt(e.target.value); setCursor(e.target.selectionStart); setDismissed(false); setSelected(0) }} onClick={e => { setCursor(e.currentTarget.selectionStart); setDismissed(false) }} onKeyUp={e => { if (['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(e.key)) { setCursor(e.currentTarget.selectionStart); setDismissed(false) } }} onKeyDown={onKey}/>
      {isOpen && <div className="mention-menu" id="token-options" role="listbox" aria-label="Design tokens"><div className="mention-heading">DESIGN TOKENS <span>{repo?.name}</span></div><div className="mention-options">{options.length ? options.map((t, i) => <button key={t.name} role="option" aria-selected={i === selected} id={`mention-${i}`} className={i === selected ? 'highlighted' : ''} onMouseDown={e => e.preventDefault()} onClick={() => insertToken(t)}><TokenMark token={t}/><code>{t.name}</code><span>{t.value}</span>{i === selected && <span>↵</span>}</button>) : <p className="empty-menu">No matching tokens. Try another name.</p>}</div><div className="mention-footer"><span>↑ ↓ to navigate</span><span>↵ to insert</span><span>esc to close</span></div></div>}
      <div className="composer-bottom"><button className="token-trigger" onClick={() => { const text = `${prompt}${prompt && !/\s$/.test(prompt) ? ' ' : ''}#`; setPrompt(text); setCursor(text.length); setDismissed(false); setSelected(0); input.current?.focus() }}><span>#</span> Reference a token</button><div><span className="keyboard-hint">⌘ ↵</span><button className="send-button" aria-label="Prepare agent prompt" disabled={!prompt.trim()} onClick={preparePrompt}><Icon name="arrow" size={18}/></button></div></div></div>
      <div className="suggestions"><span>Try a prompt</span>{['Update the card border', 'Use the accent color', 'Adjust the corner radius'].map((label, i) => <button key={label} onClick={() => { const text = `${['Update the card border to ', 'Use the accent color ', 'Adjust the corner radius to '][i]}#`; setPrompt(text); setCursor(text.length); setDismissed(false); setSelected(0); input.current?.focus() }}>{label}<span>↗</span></button>)}</div>
      </section>
      <section className="token-section"><div className="token-section-heading"><div><h2>Design tokens <span className="count-badge">{tokens.length}</span></h2><p>A single source of truth, pulled straight from your codebase.</p></div><button className="text-button" onClick={() => { setFileError(''); setModal(repo?.demo ? 'demo-sync' : 'connect') }}><Icon name="sync" size={14}/> {repo?.demo ? 'Sample tokens' : 'Re-import tokens'}</button></div>
      <div className="token-toolbar"><div className="tabs">{categories.map(cat => <button key={cat} className={category === cat ? 'active' : ''} onClick={() => setCategory(cat)}>{cat === 'Color' ? 'Colors' : cat === 'Class' ? 'Classes' : cat}{category === cat && <span>{tokens.filter(t => cat === 'All tokens' || t.type === cat).length}</span>}</button>)}</div><label className="search-input"><Icon name="search" size={15}/><input aria-label="Search tokens" placeholder="Search tokens…" value={search} onChange={e => setSearch(e.target.value)}/><span>⌕</span></label></div>
      <div className="table-wrap"><table><thead><tr><th>TOKEN NAME</th><th>VALUE</th><th>TYPE</th><th>SOURCE</th><th/></tr></thead><tbody>{visible.slice(0, view === 'library' ? undefined : 8).map(token => <tr key={token.name} onClick={() => setDetail(token)}><td><TokenMark token={token}/><code>{token.name}</code></td><td><code>{token.value}</code></td><td><span className="type-badge">{token.type}</span></td><td><Icon name="code" size={12}/>{token.source}</td><td><button title="Insert token into prompt" aria-label={`Insert ${token.name}`} onClick={e => { e.stopPropagation(); insertToken(token) }}><Icon name="plus" size={14}/></button></td></tr>)}</tbody></table>{!visible.length && <div className="empty-state">No tokens match your search.<button onClick={() => { setSearch(''); setCategory('All tokens') }}>Clear filters</button></div>}</div>
      <div className="table-footer"><span>Showing {Math.min(visible.length, view === 'library' ? visible.length : 8)} of {visible.length} tokens</span><button onClick={() => { setView(view === 'library' ? 'workspace' : 'library') }}>{view === 'library' ? 'Back to overview' : 'View all tokens'}<Icon name="chevron" size={13}/></button></div></section></>}
      <footer className="main-footer"><span><Icon name="link" size={13}/> Built on your system. Made for your flow.</span><span className="footer-status"><span className="status-dot"/> All changes stay local</span></footer>
    </main></div>
    {notice && <div className="toast"><Icon name="check" size={17}/>{notice}</div>}
    {(modal || detail) && <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) { setModal(null); setDetail(null) } }}><section className="modal" role="dialog" aria-modal="true" aria-label={detail ? detail.name : modal || 'Dialog'}><button className="modal-close" aria-label="Close dialog" onClick={() => { setModal(null); setDetail(null) }}><Icon name="close"/></button>
      {detail ? <><span className="modal-icon"><TokenMark token={detail}/></span><h2>{detail.name}</h2><p>A {detail.type.toLowerCase()} token from {repo?.name}.</p><div className="token-detail"><label>VALUE</label><code>{detail.value}</code><label>SOURCE</label><code>{detail.source}</code><label>USAGE</label><code>{detail.type === 'Class' ? detail.name : `var(${detail.name})`}</code></div><button className="button primary" onClick={() => { insertToken(detail); setDetail(null) }}>Reference in prompt <Icon name="plus" size={16}/></button></> : modal === 'connect' ? <><span className="modal-icon"><Icon name="folder" size={25}/></span><h2>Connect your codebase</h2><p>Select a local project folder. We’ll find CSS variables and classes in your stylesheets and add them to your token library.</p><div className="import-note"><Icon name="code"/><div><strong>Your code stays yours</strong><p>Files are read in your browser. Only extracted tokens are saved on this device. Re-import to pick up changes.</p></div></div><input ref={folderInput} type="file" multiple {...{ webkitdirectory: '' }} style={{ display: 'none' }} onChange={connect}/><button className="button primary wide" disabled={loading} onClick={() => folderInput.current?.click()}><Icon name="folder"/>{loading ? 'Reading stylesheets…' : 'Choose project folder'}</button>{fileError && <p className="error">{fileError}</p>}<small className="modal-footnote">Supports CSS, SCSS, Sass, and Less · No account required</small></> : modal === 'output' ? <><span className="modal-icon"><Icon name="sparkle" size={25}/></span><h2>A little context goes a long way.</h2><p>Your prompt is ready, with resolved design tokens. Copy it into your coding agent to make the change.</p><textarea className="output" readOnly value={output}/><button className="button primary wide" onClick={() => copy(output)}>Copy agent prompt <Icon name="external" size={16}/></button></> : modal === 'settings' ? <><h2>Workspace settings</h2><p>Manage codebases saved on this device.</p><div className="settings-list">{repos.map(r => <div key={r.id}><span><strong>{r.name}</strong><small>{r.tokens.length} tokens · {r.demo ? 'Example' : 'Local import'}</small></span><button className="text-button danger" onClick={() => { setRepos(prev => prev.filter(x => x.id !== r.id)); setNotice(`${r.name} disconnected`) }}>Disconnect</button></div>)}</div><button className="button" onClick={() => { if (!repos.some(r => r.id === demoRepo.id)) setRepos(prev => [...prev, demoRepo]); setNotice('Example codebase is available') }}>Restore example codebase</button></> : modal === 'workspace' ? <><h2>Your personal workspace</h2><p>This workspace lives in your browser. Connect local codebases to build your own design vocabulary.</p><div className="workspace-summary"><strong>{repos.length}</strong> connected codebases <strong>{repos.reduce((n, r) => n + r.tokens.length, 0)}</strong> available tokens</div><button className="button primary" onClick={() => setModal('connect')}>Connect a codebase</button></> : modal === 'demo-sync' ? <><h2>Meet the example design system</h2><p>These {initialTokens.length} sample tokens let you explore DesignSnippets. Connect your own project to see real CSS variables and classes from your codebase.</p><button className="button primary" onClick={() => setModal('connect')}>Connect your codebase</button></> : <><span className="modal-icon">#</span><h2>Same language. Better results.</h2><p>Bring exact design system references into your next agent prompt.</p><ol className="help-steps"><li><strong>Connect a codebase</strong><p>Choose a local folder with CSS variables or stylesheet classes.</p></li><li><strong>Say it with a #</strong><p>Type # in the composer, search for a token, then press Enter or click to insert it.</p></li><li><strong>Give your agent context</strong><p>Use the send button to prepare a prompt with token values and source files, then copy it to your coding agent.</p></li></ol><button className="button primary" onClick={() => { setModal(null); input.current?.focus() }}>Let’s try it <Icon name="chevron" size={16}/></button></>}
    </section></div>}
  </div>
}
export default App
