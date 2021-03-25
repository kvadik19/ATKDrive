let tick = 0;		// Timeout handler/
let bodyIn = document.querySelector('.tabContent.shown .qw_recv');
let bodyOut = document.querySelector('.tabContent.shown .qw_send');
let keyItems = document.querySelectorAll('#keySelect li');

let subSwitch = function(tab) {
		let cook = getCookie('acTab');
		let def = {};
		if ( cook ) def = JSON.parse( decodeURIComponent(cook) );

		if ( tab && tab.matches('.subTab') ) {			// Store selected subtab state
			let list = tab.parentNode;
			def[list.dataset.type] = tab.dataset.name;
			setCookie('acTab', encodeURIComponent(JSON.stringify(def)), 
						{ 'path':'/', 'domain':document.location.host,'max-age':60*60*24*365 } );
			list.querySelectorAll('.subTab').forEach( t =>{t.className = t.className.replace(/\s*active/,'')});
			tab.className += ' active';
			dispatch.display();

		} else {			// Apply stored subtab state
			let list = document.querySelector('.tabContent.shown .subTabs');
			if ( def[list.dataset.type] ) {		// Have cookie?
				let tab = list.querySelector('.subTab[data-name="'+def[list.dataset.type]+'"]');
				if ( tab ) {
					list.querySelectorAll('.subTab').forEach( t =>{t.className = t.className.replace(/\s*active/,'')});
					tab.className += ' active';
					dispatch.display();
				} else {
					subSwitch(list.firstElementChild);		// Or activate first
				}
			} else {
				subSwitch(list.firstElementChild);		// Or activate first
			}
		}
	};

let showQRY = function(host, query) {
		if ( query.code ) {
			let code = host.querySelector('.qwHdr code');
			code.innerHTML = '';
			code.innerText = query.code;
		}
		if ( query.data ) {
			let data = host.querySelector('.qw_data');
			data.innerHTML = '';
			data.appendChild( toDOM( query.data) );
		}
	};

function init() {
	return fromDOM(document.querySelector('.tabContent.shown .qw_recv .qw_data'));
}

let ino = 0;

let fromDOM = function(node) {
		console.log('Pass '+(ino++));
		let dom;
		let getVal = function(item) {
				let res = {};
				if ( item.firstChild.matches('.keyVal') ) {
					res.val = item.firstChild.innerText;

				} else if (item.firstChild.matches('.keyName') 
							&& item.lastChild.matches('.keyVal') ) {
					res.key = item.firstChild.innerText;
					res.val= item.lastChild.innerText;

				} else if( item.lastChild ) {
					if ( item.firstChild.matches('.keyName') ) {
						res.key = item.firstChild.innerText;
					}
		console.log( item.lastChild );
		// 			res.val='DOM';
					res.val = fromDOM(item.lastChild);
				}
		console.log(res);
				return res;
			};

		if ( node.className === 'domItem') node = node.firstChild;
		if ( node.matches('.array') ) {
			dom = [];
			for (nC=0; nC<node.children.length; nC++) {
				if ( node.children[nC].matches('.same') ) break;
				let res = getVal(node.children[nC]);
				if ( res.key ) {
					dom.push(res);
				} else {
					dom.push(res.val);
				}
			}
		} else if ( node.matches('.object') ) {
			dom  = {};
			for (nC=0; nC<node.children.length; nC++) {
				let res = getVal(node.children[nC]);
				dom[res.key] = res.val;
			}
		} else if ( node.matches('.value') ) {
			console.log('FromDom value');
			let res = getVal(node);
			if ( res.key ) {
				dom = {};
				dom[res.key] = res.val;
			} else {
				dom = res.val;
			}
			
		} else if ( node.firstChild ) {
			dom = fromDOM(node.firstChild);
		}
console.log(dom);
		return dom;
	};
	
let toDOM = function(val, key) {
		let div = createObj('div',{'className':'domItem'});
		if ( val.constructor.toString().match(/Array/) ) {
			let inner = toDOM( val[0] );
			let content = createObj('div',{'className':'domItem array'});
			let stub = createObj('div', {'className':'domItem same','innerText':'<--->',
							'title':'Подразумевается что массив [] содержит равнозначные по типу и структуре элементы' });
			if ( key ) {
				div.className += ' value';
				div.innerHTML = '<span class="keyName">'+key+'</span>:';
				content.appendChild( inner);
				if ( val.length > 1 ) {
					stub.title = stub.title.replace(/\[\]/,'['+key+']');
					content.appendChild(stub);
				}
				div.appendChild(content);
			} else {
				div.className += ' array';
				div.appendChild(inner);
				if ( val.length > 1 ) {
					stub.title = stub.title.replace(/\[\]/,'');
					div.appendChild(stub);
				}
			}
		} else if ( val.constructor.toString().match(/Object/) ) {
			let content = createObj('div',{'className':'object'});
			if ( key ) {
				div.innerHTML = '<span class="keyName">'+key+'</span>:';
				content.className += ' domItem';
				div.className += ' value';
			}
			Object.keys(val).forEach( k=>{
					content.appendChild( toDOM( val[k], k) );
				});
			div.appendChild(content);
		} else {
			div.className += ' value';
			div.innerHTML = '<span class="keyVal">'+val+'</span>';
			if ( key ) div.innerHTML = '<span class="keyName">'+key+'</span>:<span class="keyVal">'+val+'</span>';
		}
		return div;
	};

let dispatch = {		// Switching between Tabs/subTabs dispatcher
		display: function() {
				let type = document.querySelector('.tabContent.shown .subTabs').dataset.type;
				let method = document.querySelector('.tabContent.shown .subTab.active').dataset.type;
				bodyIn = document.querySelector('.tabContent.shown .qw_recv');
				bodyOut = document.querySelector('.tabContent.shown .qw_send');
				if (bodyOut) {
					bodyOut.onclick = function(e) {		// Deselect JSONs
							if ( e.path.findIndex( i =>{ 
											return ( i.nodeType === 1 && (i.matches('.jsonItem') || i.type === 'button') ) 
										}) < 0 ) {
								document.querySelectorAll('.jsonItem').forEach( 
									
									i =>{ i.className = i.className.replace(/\s*active/g,'')});
								btnActivate();
							}
						};
				}
				keyTool.init();
				btnActivate();
				this[type][method]();
			},
		ext: {
				read: function() {
						return true;
					},
				write: function() {
						console.log('Draw Write');
						return true;
					}
			},
		int: {
				rw: function() {
						console.log('Draw Read/Write');
						return true;
					},
			},
	};

let keyTool = {			// Add key-value floating window operations
		init: function() {
				document.querySelectorAll('#keySelect li.choosd').forEach( i =>{ i.className = i.className.replace(/\s*choosd/g,'')});
				document.querySelectorAll('#keySelect li').forEach( i =>{ i.onclick = keyTool.liChoose;
																		i.ondblclick = keyTool.result });
				document.querySelector('#keySelect button.esc').onclick = this.keyHide;
				document.querySelector('#keySelect button.ok').onclick = this.result;
				document.querySelector('#keySelect input[type="text"]').oninput = this.inpCheck;
				document.querySelector('#keySelect button.ok').setAttribute('disabled',1);
			},
		keyList: document.querySelectorAll('#keySelect li'),
		panel: document.getElementById('keySelect'),
		keyHide:function() { document.getElementById('keySelect').style.display = 'none'; 
				document.documentElement.onclick = null;
				bodyOut.querySelector('button[data-action="key"]').removeAttribute('disabled');
			},
		keyTrap: function(evt) {			// Click outside of keySelect window
				if ( evt.path.findIndex( i =>{ return ( i.nodeType === 1 && i.matches('.over-panel')) }) < 0 ) keyTool.keyHide();
			},
		fire: function( callbk ) {
				this.callbk = callbk;
				document.querySelectorAll('#keySelect li.active').forEach( i =>{ i.className = i.className.replace(/\s*active/g,'')});
				document.querySelector('#keySelect input[type="text"]').value = '';
				document.documentElement.onclick = this.keyTrap;
				document.querySelector('#keySelect button.ok').setAttribute('disabled',1);
				bodyOut.querySelector('button[data-action="key"]').setAttribute('disabled',1);

				if ( !this.panel.style.top ) {
					this.panel.style.top = bodyOut.offsetTop+'px';
					this.panel.style.left = bodyOut.offsetLeft+'px';
				}
				this.panel.style.display = 'block';
				let [X, Y, W, H] = [this.panel.offsetLeft, this.panel.offsetTop,
									this.panel.offsetWidth, this.panel.offsetHeight];
				if (X < 0) { X = 20 } 
				else if (X + W > window.innerWidth) { X = window.innerWidth - W - 20 }
				if (Y < window.scrollY) { Y = window.scrollY + 20 }
				else if (Y + H > window.scrollY+window.innerHeight) { Y = window.scrollY+window.innerHeight - H - 20 }
				this.panel.style.left = X+'px';
				this.panel.style.top = Y+'px';
			},
		result: function() {
				let key = document.querySelector('#keySelect input[type="text"]');
				let val = document.querySelector('#keySelect li.active') 
										|| {'innerText':'','className':''};		// NOW Allow empty value!
				val.className = val.className.replace(/\s*choosd/g,'');		// Prevent
				val.className += ' choosd';
				if ( typeof(keyTool.callbk) === 'function' ) {
					keyTool.callbk(key.value, val.cloneNode(true) );		// Pass into callback just a LI copy
				}
				keyTool.keyHide();
			},
		liChoose: function(evt) {
				document.querySelectorAll('#keySelect li.active').forEach( i =>{ i.className = i.className.replace(/\s*active/g,'')});
				let li = evt.target;
				let txt = document.querySelector('#keySelect input[type="text"]');
				li.className += ' active';
				if ( txt.value.replace(/\s/g,'').length === 0 
						|| document.querySelector('#keySelect li[data-name="'+txt.value+'"]') ) {
					txt.value = li.innerText;		// Not manual keyName typed
				}
				keyTool.inpCheck();
			},
		inpCheck: function(evt) {		// Check for some of list selected
				let txt = document.querySelector('#keySelect input[type="text"]');
				let li = document.querySelector('#keySelect li.active') || true;		// Ignore this check - allow empty keyName
				if ( txt.value.replace(/\s/g,'').length > 0 && li ) {					// Stub for ignore list checking is being used!
					document.querySelector('#keySelect button.ok').removeAttribute('disabled');
				} else {
					document.querySelector('#keySelect button.ok').setAttribute('disabled',1);
				}
			},
	};

let rollUp = function(evt) {		// Rollup JSON divs
		if ( !evt.target.matches('.preset') ) return;
		evt.stopImmediatePropagation();
		if ( evt.target.matches('.shorten') ) {
			evt.target.className = evt.target.className.replace(/\s*shorten/g,'');
		} else {
			evt.target.className += ' shorten';
		}
	};

let keyEdit = {
		action: function(evt) {
				this.target = evt.target;
				let [w, h] = [evt.target.offsetWidth, evt.target.offsetHeight];
				keyEdit.preval = evt.target.innerText;
				evt.target.innerHTML = '';
				let inpt = createObj('input',{'type':'text','className':'jsonKeyEdit',
						'style.width':w+'px','style.height':h+'px',
						'value':keyEdit.preval,
						'onblur':keyEdit.killInpt,'onkeydown':keyEdit.keyOut });
				evt.target.appendChild(inpt);
				inpt.focus();
				inpt.select();
			},
		killInpt: function(evt) {
				let host = evt.target.closest('.keyName');
				let value = evt.target.value;
				host.removeChild(evt.target);
				if ( value.replace(/\s+/g,'').length > 0) {
					host.innerText = value;
					let preset = host.closest('.preset');
					if ( preset ) {
						let keyVal = host.parentNode;
						let sel = preset.className.replace(/ +/g,'.');
						sel = '.'+sel+' .'+keyVal.className.replace(/ +/g,'.')+'[data-name="'+keyVal.dataset.name+'"] .keyName';
						bodyOut.querySelectorAll(sel).forEach( el =>{ el.innerText = value});
					}
				} else {
					host.innerText = keyEdit.preval;
				}
			},
		keyOut: function(evt) {
				if ( evt.code.match(/Enter|Tab/) ) {
					evt.preventDefault();
					evt.target.blur();
				} else if ( evt.code.match(/Escape/) ) {
					evt.target.value = keyEdit.preval;
					evt.target.blur();
				}
			}
	};

let jsonEdit = {			// Json elements buttons operations
		list: function(body) {
				let el = createObj('div',{'id':Date.now(),'className':'domItem jsonItem array active','innerHTML':'&nbsp;','onclick':jsonSelect});
				this.place(body, el);
			},
		hash: function(body) {
				let el = createObj('div',{'className':'domItem'});
				el.appendChild(createObj('div',{'id':Date.now(),'className':'jsonItem object active','innerHTML':'&nbsp;','onclick':jsonSelect}));
				this.place(body, el);
			},
		key: function(body) {				// Append values from users, media tables
				keyTool.fire( function(key, val) {
								let text = val.innerText.replace(/^[\s\n]+|[\s\n]+$/g,'');
								let el = createObj('div',{'id':Date.now(),'className':'domItem jsonItem value',
															'data-name':text,'onclick':jsonSelect,'title':val.title});
								el.appendChild(createObj('span',{'className':'keyName','innerText':key,'ondblclick':keyEdit.action}));
								el.insertAdjacentText('beforeend',':');
								let keyVal = createObj('span',{'className':'keyVal','innerText':text});
								if ( val.dataset.list == '1') {
									keyVal = createObj('div',
												{'className':'domItem array preset shorten','onclick':rollUp});	// Unchangeable item
									let mBox = createObj('div',{'className':'domItem'});
									let mDef = createObj('div',{'className':'object media','data-name':text});
									media.forEach( m =>{
										let keyName = m.name;
										let keySample = bodyOut.querySelector('.domItem.array.preset '
															+'.domItem.value.media[data-name="'
															+m.name+'"] .keyName');	// Obtain changed name
										if ( keySample ) keyName = keySample.innerText;
										let mFile = createObj('div',
														{'className':'domItem value media','data-name':m.name,'title':m.title});
										let mName = createObj('span',
														{'className':'keyName','innerText':keyName,'ondblclick':keyEdit.action});
										let mVal = createObj('span',{'className':'keyVal','innerText':'$'+m.name});
										mFile.appendChild(mName);
										mFile.insertAdjacentText('beforeend',':');
										mFile.appendChild(mVal);
										mDef.appendChild(mFile);
									});
									mBox.appendChild(mDef);
									keyVal.appendChild(mBox);
									keyVal.appendChild(createObj('div',{'className':'domItem same','innerText':'<--->',
															'title':'Подразумевается что массив ['+text
															+'] содержит равнозначные по типу и структуре элементы' }));
								} else if ( text.length > 0 ) {
									keyVal.innerText = '$'+ text;
								}
								el.appendChild(keyVal);
								jsonEdit.place(body, el);

							});
			},
		del: function(body) {
				let selected = bodyOut.querySelectorAll('.qw_data .jsonItem.active');
				if ( selected.length > 0 ) {
					selected.forEach( i =>{ try { 
												let d = i.closest('.domItem');
												let b = d.parentNode;
												b.removeChild(d);
												if ( b.firstElementChild.matches('.same') ) b.removeChild(b.firstElementChild);
												if ( b.lastChild.nodeType == 3) b.parentNode.removeChild(b);
									 		} catch(e) {} } );
					btnActivate();
				}
			},
		place: function(body, item) {
				let qdata = body.querySelector('.qw_data');
				let selected = qdata.querySelectorAll('.jsonItem.active');
				if ( selected.length > 0 ) {
					for (nI=0; nI<selected.length; nI++) { 
						let toAdd = true;
						let i = selected[nI];
						if ( i.matches('.array') ) {
							if ( item.matches('.value') ) {			// Leave just a value
								item.removeChild(item.querySelector('.keyName'));
								if (item.firstChild.nodeType === 3) item.removeChild(item.firstChild);
							}

							if ( i.children.length === 1 ) {
								item = createObj('div',{'className':'domItem same','innerText':'<--->',
									'title':'Подразумевается что массив содержит равнозначные по типу и структуре элементы' });
							} else if(i.children.length > 1) {
								toAdd = false;
							}
						} else if( i.matches('.value') && !item.matches('.value') ) {
							i.removeChild( i.lastElementChild );
						} else if( i.matches('.object') && !item.matches('.value') ) {
							toAdd = false;
						} else if( i.matches('.value') && item.matches('.value') ) {
							toAdd = false;
						}
						if ( toAdd ) {		// Append only once! (without duplicating item)
							if ( item.matches('.active') || item.querySelector('.active') ) {
								selected.forEach( 
										j =>{ j.className = j.className.replace(/\s*active/g,'')} );
							}
							i.appendChild(item);
							break;
						}
					}
				} else {
					qdata.appendChild(item);
				}
				btnActivate();
			}
	};
let jsonSelect = function(e) {
		e.stopImmediatePropagation();
		let el = e.target.closest('.jsonItem');
		if ( e.shiftKey ) {
			e.preventDefault();
			if ( el.matches('.active') ) {
				el.className = el.className.replace(/\s*active/g,'');
			} else {
				el.className += ' active';
			}
		} else {
			document.querySelectorAll('.jsonItem').forEach( i =>{ i.className = i.className.replace(/\s*active/g,'')});
			el.className += ' active';
		}
		btnActivate();
	};

let btnDo = document.querySelectorAll('button.dataDo');
btnDo.forEach( bt =>{
		bt.onclick = function(e) {
				e.stopImmediatePropagation();
				let action = e.target.dataset.action;
				jsonEdit[action](bodyOut);
			};
	});

let btnActivate = function() {
		btnDo.forEach( bt =>{
				if ( bt.dataset.skip ) {
					let skip = bt.dataset.skip;
					bt.removeAttribute('disabled');
					let toDis = '';
					let selectors = skip.split('&&');
					selectors.forEach( ss =>{
							let selector = ss.substring(ss.indexOf('!')+1 )
							let test = bodyOut.querySelector(selector) ? true : false;
							if ( ss.match(/!/) ) test = !test;
							if ( typeof(toDis) === 'string' ) {
								toDis = test;
							} else {
								toDis = (toDis && test);
							}
						});
					if ( toDis ) bt.setAttribute('disabled', 1);
				}

			});
	};

let tabs = document.querySelectorAll('.subTab:not(.fail)');
tabs.forEach( st =>{
		st.onclick = function(e) { if (e.target.matches('.active')) return;
					let tab = e.target;
						subSwitch( tab );
				};
	});

let qState = function(state) {
		if (state == 1) {
			document.getElementById('listen').disabled = true;
			document.getElementById('abort').style.display = 'initial';
		} else {
			window.clearTimeout(tick);
			flush({'code':'watchdog', 'data':{'cleanup':1}}, url);
			document.getElementById('listen').disabled = false;
			document.getElementById('abort').style.display = 'none';
			document.getElementById('tunit').innerText = 'минут';
			document.getElementById('tout').innerText = timeout;
		}
	};
document.getElementById('abort').onclick = qState;
document.getElementById('listen').onclick = function(e) {
		let btn = this;
		qState(1);
		let tstart = Date.now();
		let msg_send = {'code':'watchdog', 'data':{'timeout':period}};

		let msgGot = function(msg) {
				if ( msg.match(/^[\{\[]/) ) msg = JSON.parse(msg);
				if ( msg.data ) {
					if ( msg.data.match(/^[\{\[]/) ) msg = JSON.parse(msg.data);
					showQRY(bodyIn, msg);
					qState(0);
				} else if( Date.now() > tstart+timeout*60000 ) {
					qState(0);
				} else {
					let left = timeout*60 - Math.round( (Date.now()-tstart)/1000 );
					if (left < 60) {
						document.getElementById('tunit').innerText = 'секунд';
					} else {
						left = Math.round(left/60);
					}
					document.getElementById('tout').innerText = left;
					tick = window.setTimeout( function() { flush(msg_send, url, msgGot) }, period*1000);
				}
			};
		flush(msg_send, url, msgGot);
	};

document.getElementById('codeSync').onclick = function(e) {
		let inCode = bodyIn.querySelector('.qw_code code').innerText;
		if ( inCode ) bodyOut.querySelector('.qw_code #code').value = inCode;
	};
