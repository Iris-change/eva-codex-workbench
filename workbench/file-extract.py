#!/usr/bin/env python3
"""Bounded local text extraction. Never executes file content or unpacks archives."""
import sys, json, zipfile, re, subprocess, xml.etree.ElementTree as ET
from pathlib import Path
from html.parser import HTMLParser
LIMIT=512000
TEXTUTIL_EXT={'.doc','.rtf'}
TEXT_EXT={'.txt','.md','.markdown','.json','.jsonl','.csv','.tsv','.log','.xml','.svg','.yaml','.yml','.toml','.ini','.conf','.py','.js','.ts','.tsx','.jsx','.html','.htm','.css','.scss','.swift','.m','.mm','.h','.c','.cpp','.rs','.go','.java','.kt','.sh','.zsh','.bash','.sql','.r','.ipynb','.env','.tex','.srt','.vtt'}
def clip(text,label,kind='document'):
 return {'text':text[:LIMIT], 'kind':kind, 'label':label, 'truncated':len(text)>LIMIT}
def xmltext(node):return ''.join(node.itertext())
def office(p,ext):
 with zipfile.ZipFile(p) as z:
  info=z.infolist()
  if len(info)>10000:raise ValueError('压缩包条目过多')
  budget=24*1024*1024
  def read(name):
   nonlocal budget
   i=z.getinfo(name)
   if i.file_size>8*1024*1024 or i.file_size>budget:raise ValueError('文档解压后的内容过大')
   budget-=i.file_size
   return ET.fromstring(z.read(name))
  names=z.namelist()
  if ext=='.docx':
   root=read('word/document.xml');parts=[''.join(p.itertext()) for p in root.iter() if p.tag.endswith('}p')]
   return clip('\n'.join(parts),'Word 正文文字')
  if ext=='.pptx':
   slides=sorted([n for n in names if re.fullmatch(r'ppt/slides/slide\d+\.xml',n)],key=lambda n:int(re.search(r'slide(\d+)',n).group(1)))
   return clip('\n\n'.join('幻灯片 '+str(i+1)+'\n'+'\n'.join(n.text or '' for n in read(name).iter() if n.tag.endswith('}t')) for i,name in enumerate(slides[:500])),'PPT 幻灯片文字')
  if ext=='.xlsx':
   shared=[]
   if 'xl/sharedStrings.xml' in names:shared=[xmltext(n) for n in read('xl/sharedStrings.xml') if n.tag.endswith('}si')]
   sheets=sorted((n for n in names if re.fullmatch(r'xl/worksheets/sheet\d+\.xml',n)),key=lambda n:int(re.search(r'sheet(\d+)\.xml',n).group(1)));parts=[]
   titles={}
   try:
    if 'xl/workbook.xml' in names and 'xl/_rels/workbook.xml.rels' in names:
     targets={r.get('Id'):r.get('Target','') for r in read('xl/_rels/workbook.xml.rels') if r.tag.endswith('}Relationship')}
     order=[]
     for sh in read('xl/workbook.xml').iter():
      if not sh.tag.endswith('}sheet'):continue
      rid=next((v for k,v in sh.attrib.items() if k.endswith('}id')),None);t=targets.get(rid,'').lstrip('/')
      t=t if t.startswith('xl/') else 'xl/'+t
      if t in names:titles[t]=sh.get('name') or t;order.append(t)
     sheets=order+[n for n in sheets if n not in order]
   except (ET.ParseError,KeyError):pass
   for name in sheets[:100]:
    rows=[];size=0
    for row in read(name).iter():
     if not row.tag.endswith('}row'):continue
     cells=[]
     for c in row:
      value=next((x.text or '' for x in c if x.tag.endswith('}v')),'')
      if c.get('t')=='s':value=shared[int(value)] if value.isdigit() and int(value)<len(shared) else value
      elif c.get('t')=='inlineStr':value=xmltext(c)
      cells.append(c.get('r','')+'='+value)
     rows.append('\t'.join(cells));size+=len(rows[-1])
     if size>LIMIT:break
    parts.append('工作表 '+titles.get(name,name.rsplit('/',1)[-1][:-4])+'\n'+'\n'.join(rows))
   return clip('\n\n'.join(parts),'Excel 单元格文字（公式使用文件内缓存结果）')
  if ext in {'.odt','.ods','.odp'}:return clip(xmltext(read('content.xml')),'OpenDocument 文字')
  return clip('\n'.join(i.filename+' ('+str(i.file_size)+' bytes)' for i in info[:2000]),'压缩包目录 · 未解压')
def textutil(p,ext):
 r=subprocess.run(['/usr/bin/textutil','-convert','txt','-encoding','UTF-8','-stdout',str(p)],capture_output=True,timeout=12)
 if r.returncode!=0:raise ValueError('textutil 无法读取此文档')
 text=r.stdout.decode('utf-8','replace')
 if not text.strip():return {'kind':'file','label':'原文件 · 未提取到文字','warning':'文档中没有可读取的文字，可能只有图片或受保护内容。'}
 return clip(text,{'.doc':'Word 97-2004 正文文字','.rtf':'RTF 正文文字'}.get(ext,'文档文字'))
def extract(p,ext):
 if ext in TEXTUTIL_EXT and Path('/usr/bin/textutil').exists():return textutil(p,ext)
 if ext in {'.docx','.xlsx','.pptx','.odt','.ods','.odp','.zip'}:return office(p,ext)
 data=p.read_bytes()
 if ext=='.pdf':return {'kind':'file','label':'PDF 原文件 · 可用工具读取','warning':'未提取到文字；扫描件、加密 PDF 或特殊排版需用支持的工具查看。'}
 if ext in TEXT_EXT or (b'\0' not in data[:8192] and not any(x<9 or 13<x<32 for x in data[:8192])):
  text=None
  encodings=['utf-8-sig','utf-16'] if data[:2] in {b'\xff\xfe',b'\xfe\xff'} else ['utf-8-sig']
  if ext in TEXT_EXT:encodings.append('gb18030')
  for encoding in encodings:
   try:text=data.decode(encoding);break
   except (UnicodeError,LookupError):pass
  if text is not None:return clip(text,'文本 · 可直接读取','text')
 return {'kind':'file','label':'原文件 · 需工具读取','warning':'本机没有此格式的内容解析器，原文件已保留。音视频、可执行文件等不会被自动执行或当作文字读取。'}
try:print(json.dumps(extract(Path(sys.argv[1]),sys.argv[2].lower()),ensure_ascii=False))
except Exception as e:print(json.dumps({'kind':'file','label':'原文件 · 解析未完成','warning':str(e)[:200]},ensure_ascii=False))
