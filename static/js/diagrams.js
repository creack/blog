function drawSequenceDiagrams() {
  var x = document.getElementsByClassName('language-sequence');
  for (i = 0; i < x.length; i++) {
    var diagram = Diagram.parse(x[i].innerText);
    x[i].innerHTML = '';
    x[i].setAttribute('id', 'diagram-sequence-' + i);
    diagram.drawSVG('diagram-sequence-' + i, {theme: 'simple'})
  }
}

function drawFlowDiagrams() {
  var x = document.getElementsByClassName('language-flow');
  for (i = 0; i < x.length; i++) {
    var diagram = flowchart.parse(x[i].innerText);
    x[i].innerHTML = '';
    x[i].setAttribute('id', 'diagram-flow-' + i);
    diagram.drawSVG('diagram-flow-' + i)
  }
}

drawSequenceDiagrams();
drawFlowDiagrams();
