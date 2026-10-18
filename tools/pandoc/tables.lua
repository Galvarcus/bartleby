-- tools/pandoc/tables.lua: the table options of Bartleby compile, a Pandoc
-- Lua filter. Bartleby passes them as metadata, after its fallbacks, see
-- TableOpts in autoload/bartleby/compile.vim:
--
--   table-header  bold, italic, smallcaps, or plain: the text of the header
--                 cells, in every format.
--   table-border  none or single: the frame around a table.
--   table-vlines  none or single: the lines between its columns.
--
-- Pandoc writes a LaTeX table with booktabs rules and no vertical lines,
-- and has no option for them. With a border or lines, this filter lets
-- Pandoc write the table, and then changes its column spec, and its rules
-- to \hline, because booktabs rules leave a gap beside a vertical line.
-- HTML and EPUB get their lines from CSS, see WriteOverrideCss.
-- REFERENCE: https://github.com/jgm/pandoc/issues/922

local WRAP = {
  bold = pandoc.Strong,
  italic = pandoc.Emph,
  smallcaps = pandoc.SmallCaps,
}
local NONE = 'none'

local function opt(meta, key, default)
  local value = meta[key]
  return value ~= nil and pandoc.utils.stringify(value) or default
end

-- Wrap the text of each header cell in wrap, a Pandoc inline element.
local function style_header(tbl, wrap)
  local function each(block)
    if #block.content > 0 then
      block.content = { wrap(block.content) }
      return block
    end
  end
  for _, row in ipairs(tbl.head.rows) do
    for _, cell in ipairs(row.cells) do
      cell.contents = cell.contents:walk({ Plain = each, Para = each })
    end
  end
end

-- The columns of a longtable spec, without the @{} at its ends: l, c, r,
-- or >{...}p{...}. nil for a spec of another form, which is left alone.
local function split_columns(spec)
  local s = spec:gsub('^%s*@{}', ''):gsub('@{}%s*$', '')
  local cols, i = {}, 1
  while i <= #s do
    local c = s:sub(i, i)
    if c:match('%s') then
      i = i + 1
    elseif c:match('[lcr]') then
      cols[#cols + 1] = c
      i = i + 1
    else
      local first, last = s:find('^>%b{}%s*p%b{}', i)
      if not first then
        return nil
      end
      cols[#cols + 1] = s:sub(first, last)
      i = last + 1
    end
  end
  return cols
end

-- The table as LaTeX with a border, lines between its columns, or both,
-- or nil when the spec has a form that this filter does not know.
local function lined_latex(tbl, border, vlines)
  local tex = pandoc.write(pandoc.Pandoc({ tbl }), 'latex')
  local first, last = tex:find('\\begin{longtable}%[%]%b{}')
  if not first then
    return nil
  end
  local head = tex:sub(first, last)
  local cols = split_columns(head:match('%[%]{(.*)}$'))
  if not cols then
    return nil
  end
  -- A border adds the outer padding that @{} took away, and each rule
  -- takes its width from the columns, so that the table keeps its width.
  local rules = (border and 2 or 0) + (vlines and #cols - 1 or 0)
  local pad = border and 2 or 0
  local function width(name, n)
    return string.format('\\%s - %d\\tabcolsep - %d\\arrayrulewidth', name, tonumber(n) + pad, rules)
  end
  for k, col in ipairs(cols) do
    -- Pandoc writes \linewidth, and before 3.2 \columnwidth.
    cols[k] = col:gsub('\\(%a-width) %- (%d+)\\tabcolsep', width)
  end
  local edge = border and '|' or '@{}'
  local spec = edge .. table.concat(cols, vlines and '|' or '') .. edge
  tex = tex:sub(1, first - 1) .. '\\begin{longtable}[]{' .. spec .. '}' .. tex:sub(last + 1)
  tex = tex:gsub('\\toprule', '\\hline'):gsub('\\midrule', '\\hline'):gsub('\\bottomrule', '\\hline')
  return pandoc.RawBlock('latex', tex)
end

function Pandoc(doc)
  local header = opt(doc.meta, 'table-header', 'bold')
  local wrap = WRAP[header]
  local border = opt(doc.meta, 'table-border', NONE) ~= NONE
  local vlines = opt(doc.meta, 'table-vlines', NONE) ~= NONE
  local latex = FORMAT:match('latex') ~= nil
  local raw = false
  doc.blocks = doc.blocks:walk({
    Table = function(tbl)
      if wrap then
        style_header(tbl, wrap)
      end
      if latex and (border or vlines) then
        local block = lined_latex(tbl, border, vlines)
        if block then
          raw = true
          return block
        end
      end
      return tbl
    end,
  })
  -- A table written as LaTeX is no table to Pandoc, so the template must
  -- still learn that the document has one, for its table packages.
  if raw then
    doc.meta.tables = true
  end
  return doc
end
