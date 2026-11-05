(() => {
  function appendInline(parent, source) {
    const pattern = /\[([^\]]+)\]\(([^)]+)\)(\s*\{button\})|(\*\*|__)(.+?)\4|(\*|_)(.+?)\6|`([^`]+)`/g;
    let cursor = 0;
    let match;

    while ((match = pattern.exec(source))) {
      if (match.index > cursor) parent.append(document.createTextNode(source.slice(cursor, match.index)));

      let node;
      if (match[1] !== undefined) {
        let parsed;
        try {
          parsed = new URL(match[2].trim(), location.href);
        } catch {}
        if (!parsed || !['http:', 'https:', 'mailto:', 'tel:'].includes(parsed.protocol)) {
          parent.append(document.createTextNode(match[0]));
          cursor = pattern.lastIndex;
          continue;
        }

        node = document.createElement('a');
        node.href = parsed.href;
        node.textContent = match[1];
        if (match[3]) node.className = 'lesson-button-link';
        if (parsed.protocol === 'http:' || parsed.protocol === 'https:') {
          node.target = '_blank';
          node.rel = 'noopener noreferrer';
        }
      } else if (match[5] !== undefined) {
        node = document.createElement('strong');
        node.textContent = match[5];
      } else if (match[7] !== undefined) {
        node = document.createElement('em');
        node.textContent = match[7];
      } else {
        node = document.createElement('code');
        node.textContent = match[8];
      }
      parent.append(node);
      cursor = pattern.lastIndex;
    }

    if (cursor < source.length) parent.append(document.createTextNode(source.slice(cursor)));
  }

  window.renderLessonMarkdown = (root, source) => {
    root.replaceChildren();
    const lines = String(source).replace(/\r\n?/g, '\n').split('\n');
    const blockStart = /^\s*(?:#{1,6}\s|[-*+]\s+|\d+[.)]\s+|>\s?|```|(?:---+|___+|\*\*\*+)\s*$)/;
    let index = 0;

    while (index < lines.length) {
      if (!lines[index].trim()) { index++; continue; }

      if (/^\s*```/.test(lines[index])) {
        index++;
        const codeLines = [];
        while (index < lines.length && !/^\s*```/.test(lines[index])) codeLines.push(lines[index++]);
        if (index < lines.length) index++;
        const pre = document.createElement('pre');
        const code = document.createElement('code');
        code.textContent = codeLines.join('\n');
        pre.append(code);
        root.append(pre);
        continue;
      }

      const heading = lines[index].match(/^\s*(#{1,6})\s+(.+)$/);
      if (heading) {
        const element = document.createElement(`h${Math.min(5, heading[1].length + 1)}`);
        appendInline(element, heading[2]);
        root.append(element);
        index++;
        continue;
      }

      if (/^\s*(---+|___+|\*\*\*+)\s*$/.test(lines[index])) {
        root.append(document.createElement('hr'));
        index++;
        continue;
      }

      if (/^\s*>\s?/.test(lines[index])) {
        const quote = document.createElement('blockquote');
        while (index < lines.length && /^\s*>\s?/.test(lines[index])) {
          const p = document.createElement('p');
          appendInline(p, lines[index++].replace(/^\s*>\s?/, ''));
          quote.append(p);
        }
        root.append(quote);
        continue;
      }

      const firstList = lines[index].match(/^\s*([-*+]\s+|\d+[.)]\s+)/);
      if (firstList) {
        const ordered = /^\d/.test(firstList[1]);
        const list = document.createElement(ordered ? 'ol' : 'ul');
        while (index < lines.length) {
          const item = lines[index].match(ordered ? /^\s*\d+[.)]\s+(.+)$/ : /^\s*[-*+]\s+(.+)$/);
          if (!item) break;
          const li = document.createElement('li');
          appendInline(li, item[1]);
          list.append(li);
          index++;
        }
        root.append(list);
        continue;
      }

      const paragraph = [];
      while (index < lines.length && lines[index].trim() && !blockStart.test(lines[index])) paragraph.push(lines[index++].trim());
      if (!paragraph.length) paragraph.push(lines[index++].trim());
      const p = document.createElement('p');
      appendInline(p, paragraph.join(' '));
      root.append(p);
    }
  };
})();
