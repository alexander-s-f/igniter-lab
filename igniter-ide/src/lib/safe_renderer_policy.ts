// igniter-lab/igniter-ide/src/lib/safe_renderer_policy.ts

export interface StateSlot {
  slot_id: string
  contract_output_ref: string // reference path to igniter contract output node
  value_kind: 'string' | 'number' | 'boolean' | 'temporal' | 'array' | 'object'
  render_policy: 'text' | 'attribute' | 'visibility' | 'class_toggle'
  fallback: any
}

export interface ViewNode {
  tag: string
  attributes: Record<string, any>
  is_component?: boolean
  component_name?: string
  trace_metadata?: {
    context?: string[]
    forms_assisted?: boolean
    warnings?: string[]
  }
  children: Array<ViewNode | string>
  state_slots?: StateSlot[]
  ui_states?: Record<string, any>
  display_rules?: any[]
  interaction_rules?: any[]
  node_params?: Record<string, any>
}

export interface SanitizedNode extends ViewNode {
  isBlockedTag: boolean
  blockedTag: string
  blockedAttrs: string[]
  warnings: string[]
}

// Strict whitelists (VCON-4, VCON-5)
export const ALLOWED_TAGS = new Set([
  'div', 'span', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'a', 'button',
  'input', 'textarea', 'label', 'table', 'thead', 'tbody', 'tr', 'th', 'td',
  'img', 'style', 'meta', 'link', 'head', 'body', 'html', 'header', 'footer',
  'section', 'nav', 'ul', 'ol', 'li', 'br', 'hr', 'text', 'component'
])

export const ALLOWED_ATTRIBUTES = new Set([
  'class', 'id', 'style', 'href', 'placeholder', 'value', 'type',
  'disabled', 'readonly', 'checked', 'src', 'alt', 'lang', 'charset',
  'rel', 'for', 'name', 'rows', 'cols', 'target'
])

// Document-level tags that should only be allowed at the very root (VCON-5)
export const DOCUMENT_ROOT_TAGS = new Set([
  'html', 'head', 'body', 'meta', 'link'
])

export function isSuspiciousUrl(url: string, tag: string, attr: string): boolean {
  const cleanUrl = url.trim().toLowerCase()
  if (cleanUrl.startsWith('javascript:')) return true
  if (cleanUrl.startsWith('vbscript:')) return true
  if (cleanUrl.startsWith('file:')) return true
  if (cleanUrl.startsWith('data:')) {
    // Only allow data:image/ for img src
    if (tag.toLowerCase() === 'img' && attr.toLowerCase() === 'src' && cleanUrl.startsWith('data:image/')) {
      return false
    }
    return true
  }
  const match = cleanUrl.match(/^([a-z0-9+.-]+):/)
  if (match) {
    const proto = match[1]
    if (proto !== 'http' && proto !== 'https' && proto !== 'mailto' && proto !== 'tel') {
      return true
    }
  }
  return false
}

export function sanitizeNode(node: ViewNode, isRoot: boolean = false): SanitizedNode {
  const warnings: string[] = []
  const blockedAttrs: string[] = []
  const sanitizedAttrs: Record<string, any> = {}

  const tagLower = node.tag.toLowerCase()

  // 1. Tag policy check (VCON-6, VCON-5)
  let isBlockedTag = !ALLOWED_TAGS.has(tagLower)

  // Block document-level tags if they appear nested (non-root positions)
  if (!isBlockedTag && DOCUMENT_ROOT_TAGS.has(tagLower) && !isRoot) {
    isBlockedTag = true
    warnings.push(`Blocked document-level tag <${node.tag}> in nested child position`)
  }

  if (isBlockedTag && !warnings.some(w => w.includes(node.tag))) {
    warnings.push(`Blocked unsafe/disallowed tag <${node.tag}>`)
  }

  // 2. Attribute policy check (VCON-6, VCON-4)
  if (node.attributes) {
    for (const [key, value] of Object.entries(node.attributes)) {
      const keyLower = key.toLowerCase()
      const valStr = String(value).trim().toLowerCase()

      const isEvent = keyLower.startsWith('on')
      const isJSUrl = isSuspiciousUrl(valStr, tagLower, keyLower)
      const isNotWhitelisted = !ALLOWED_ATTRIBUTES.has(keyLower)
      const isCssLeak = keyLower === 'style' && (/@import/i.test(valStr) || /url\s*\(/i.test(valStr))

      if (isEvent || isJSUrl || isNotWhitelisted || isCssLeak) {
        blockedAttrs.push(key)
        if (isEvent) warnings.push(`Stripped unsafe event handler: '${key}'`)
        if (isJSUrl) warnings.push(`Blocked unsafe/suspicious protocol URL in '${key}': '${value}'`)
        if (isCssLeak) warnings.push(`Blocked url()/@import inside style attribute to prevent CSS leaks`)
        if (isNotWhitelisted && !isEvent && !isJSUrl && !isCssLeak) {
          warnings.push(`Stripped non-whitelisted attribute: '${key}'`)
        }
      } else {
        sanitizedAttrs[key] = value
      }
    }
  }

  // 3. Reverse Tabnabbing prevention with token preservation (VEDGE-4)
  if (sanitizedAttrs['target'] === '_blank') {
    const existingRel = sanitizedAttrs['rel'] ? String(sanitizedAttrs['rel']) : ''
    const tokens = new Set(existingRel.split(/\s+/).filter(Boolean))
    tokens.add('noopener')
    tokens.add('noreferrer')
    sanitizedAttrs['rel'] = Array.from(tokens).join(' ')
  }

  // 4. Style tag contents check - sanitize all children (VEDGE-1, VEDGE-2)
  let children = [...node.children]
  if (tagLower === 'style') {
    children = children.map(child => {
      if (typeof child === 'string') {
        let css = child
        if (/@import/i.test(css) || /url\s*\(/i.test(css)) {
          css = css.replace(/@import/gi, '/* blocked @import */')
                   .replace(/url\s*\(/gi, '/* blocked url( */')
          warnings.push(`Sanitized <style> block contents to strip @import and url() directives`)
        }
        return css
      } else if (typeof child === 'object' && child !== null && 'tag' in child && (child as any).tag === 'text') {
        const textNode = child as ViewNode
        let textNodeChildren = [...textNode.children]
        let sanitizedAny = false
        textNodeChildren = textNodeChildren.map(tChild => {
          if (typeof tChild === 'string') {
            if (/@import/i.test(tChild) || /url\s*\(/i.test(tChild)) {
              sanitizedAny = true
              return tChild.replace(/@import/gi, '/* blocked @import */')
                           .replace(/url\s*\(/gi, '/* blocked url( */')
            }
          }
          return tChild
        })
        if (sanitizedAny) {
          warnings.push(`Sanitized <style> block contents to strip @import and url() directives`)
          return {
            ...textNode,
            children: textNodeChildren
          }
        }
      }
      return child
    })
  }

  // Mix warnings into trace_metadata for inspector visibility
  const trace_metadata = {
    ...(node.trace_metadata || {}),
    warnings: warnings.length > 0 ? warnings : undefined
  }

  return {
    ...node,
    isBlockedTag,
    blockedTag: node.tag,
    blockedAttrs,
    warnings,
    attributes: sanitizedAttrs,
    trace_metadata,
    children
  }
}
