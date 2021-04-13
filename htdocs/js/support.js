var d = document;
var ontime;

const httpStatus = {'403':'Доступ запрещен', '413':'Файл слишком велик', 
				'502':'Не работает обработчик', '500':'Сбой программы сервера',
				'503':'Сервер временно не может обрабатывать запросы',
				'301':'Ресрурс перемещен',
			};

const mimeTypes = {'ttf':'application/x-font-ttf', 'ttc':'application/x-font-ttf', 'otf':'application/x-font-opentype', 
				'woff':'application/font-woff', 'woff2':'application/font-woff2', 'svg':'image/svg+xml',
				'sfnt':'application/font-sfnt', 'eot':'application/vnd.ms-fontobject' ,
				'tif':'image/tiff', 'tiff':'image/tiff', 'bmp':'image/x-ms-bmp',
				'jpg':'image/jpeg', 'jpeg':'image/jpeg', 'jpe':'image/jpeg', 'png':'image/png', 'gif':'image/gif',
				'zip':'application/zip', 
				};

var doubleClickEvent = new MouseEvent('dblclick', {
		'view': window,
		'bubbles': true,
		'cancelable': true
	});

var responder = createRequestObject();
var flusher = function(e) {
	try {
		if (this.readyState == 4) {
			if (this.status == 200) {
				if ( this.getResponseHeader('Content-Type').match(/javascript/i) ) {
					eval( this.responseText );
				} else if ( typeof(this.hook) == 'function' ) {
					this.hook(this.responseText);
				} else {
// 					console.log(this.response.text);
				} 
				try { document.onreadystatechange() } catch(e) {};
			} else if (this.status >= 500) {
				console.log('Error 5xx '+this.responseText+'\n'+this.getAllResponseHeaders());
			} else {
				console.log("Reading from server:" + this.status);
				this.abort();		// Clean
			}
		}
	} catch( e ) {
	console.log('Processing error: '+ '\n' + e);	//+ this.responseText
// 	console.log(this.responseText);
	// Bugzilla Bug 238559 XMLHttpRequest needs a way to report networking errors
	}
	dime(0);
}


function flush( data, url, hook, nodime ) {		// Flushes data
	let formData = '';
	if ( typeof(data) === 'object' ) {
		Object.keys(data).forEach( k => {
			let val = data[k];
			if ( typeof(data[k]) === 'object' ) val = JSON.stringify(data[k]);
			formData+='&'+encodeURIComponent(k)+'='+encodeURIComponent(val);
		});
		formData = formData.substr(1);
	} else {
		formData = 'data='+encodeURIComponent(data);
	}

	let sender = createRequestObject();
	sender.hook = hook;
	sender.nodime = nodime;
	
	sender.open('POST', url, true);
	sender.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded' );
	sender.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
	sender.onreadystatechange = flusher;
	sender.send( formData );
}		// Flush ends

function createRequestObject() {
	if (typeof XMLHttpRequest === 'undefined') {
		XMLHttpRequest = function() {
			try { return new ActiveXObject("Msxml2.XMLHTTP.6.0"); }
			catch(e) {}
			try { return new ActiveXObject("Msxml2.XMLHTTP.3.0"); }
			catch(e) {}
			try { return new ActiveXObject("Msxml2.XMLHTTP"); }
			catch(e) {}
			try { return new ActiveXObject("Microsoft.XMLHTTP"); }
			catch(e) {}
			throw new Error("This browser does not support XMLHttpRequest.");
		};
	}
	return	new window.XMLHttpRequest();
}

function dime ( flag, parent ) {		// Dim screen for user wait
	if ( !parent ) parent = document.body;
	if ( !document.getElementById('cvr') ) {
		// Mouse click protection layer
		let ctop = createObj('div',{'id':'ctop','className':'dimmer','style.zIndex':1003,
			'innerHTML':'<button onClick="dime(0);responder.abort();document.location.reload();">'
				+'Cancel</button>'});
		let cvr = createObj('div',{'id':'cvr','className':'dimmer','style.zIndex':1000,'style.cursor':'wait'});
		
		let ccnt = createObj('img',{'id':'cvpb','src':'/img/pb-1_32x32.gif','style.position':'fixed',
			'style.top':'50%','style.left':'50%','style.width':'32px','style.height':'32px','style.zIndex':1002});
				// Progress bar animated gif
		cvr.appendChild(ccnt);
		cvr.appendChild(ctop);
		parent.appendChild(cvr);
	}

	if ( flag == 1 ) {
		document.getElementById('cvr').style.display='table-cell';
	} else {
		document.getElementById('cvr').style.display='none';
		clearTimeout( ontime );
	}
	return true;
}		// Dim screen for user wait

function $id(id) {
	if ( document.getElementById(id) ) {
		return document.getElementById(id);
	} else if (document.forms.length > 0) {
		for ( let nI=0; nI < document.forms.length; nI++ ) {
			if ( document.forms[nI].elements.namedItem(id) ) {
				return document.forms[nI].elements.namedItem(id);
			}
		}
	}
	return false
}

Array.prototype.grep = function (tester) {
		let res = [];
		for( let nI=0; nI < this.length; nI++ ) {
			if ( tester(this[nI]) ) {
				res.push( this[nI] );
			}
		}
		return res;
	};

function findParentBy(node,code) {
	let parent = node.parentNode;
	try {
		if ( code(parent) ) {
			return parent;
		} else {
			return findParentBy(parent,code);
		}
	} catch(e) { return null }
}

function getCookie(c_name) {
	if (document.cookie.length > 0) {
		let cooks = document.cookie.split(';');
		let re = new RegExp('^\\s*'+c_name);
		let got = cooks.grep( cook => { return cook.match(re)});
		if ( got.length > 0 ) {
			let cook = got[got.length-1];
			return decodeURIComponent( cook.split('=')[1] );
		}
	}
	return '';
};

function setCookie(name, value, options) {		// https://learn.javascript.ru/cookie
	options = options || {};
	let expires = options.expires;
	if (typeof(expires) == 'number' && expires) {
		let d = new Date();
		d.setTime(d.getTime() + expires * 1000);
		expires = options.expires = d;
	}
	if (expires && expires.toUTCString) {
		options.expires = expires.toUTCString();
	}
	value = encodeURIComponent(value);
	let updatedCookie = name + "=" + value;
	for (let propName in options) {
		updatedCookie += "; " + propName;
		let propValue = options[propName];
		if (propValue !== true) {
			updatedCookie += "=" + propValue;
		}
	}
	document.cookie = updatedCookie;
}

function objectClone(obj, ignore) {
	if ( !ignore ) ignore = [];
	if ( !ignore.constructor.toString().match(/Array/i) ) ignore = [ignore];
	if (typeof(obj) != "object" || obj == null ) return obj;
	let clone = obj.constructor();
	Object.keys(obj).forEach( function(key) {
												if ( ignore.find( function(val) { return key == val }) ) return;
												if (typeof(obj[key]) == "object") {
													clone[key] = objectClone(obj[key]);
												} else {
													clone[key] = obj[key];
												}
											}
										);
	return clone;
}

function actionStore(node, action) {		// Stores assigned event handlers for node and its childrens (for cloneNode needs)
	let ret = {};
	ret[action] = node[action];
	if (node.children.length > 0) {
		ret.subact = [];
		for ( let nn = 0; nn < node.children.length; nn++ ) {
			ret.subact.push( actionStore(node.children[nn], action) )
		}
	}
	return ret;
}

function actionSet(node, set) {		// ReStores event handlers for cloned node and its childrens (for cloneNode needs)
	let action = Object.keys(set)[0];
	node[action] = set[action];
	if ( set.subact && node.children.length > 0 ) {
		for ( let nn = 0; nn < set.subact.length; nn++ ) {
			if ( node.children[nn] ) actionSet(node.children[nn], set.subact[nn]);
		}
	}
	return true;
}

function base64Encode( stringInput ) {
	let normalizedInput = encodeURIComponent( stringInput ).replace(/%([0-9A-F]{2})/g,
				function( $0, hex ) {		// toSolidBytes
					return String.fromCharCode( "0x" + hex );
				}
			);
	return btoa( normalizedInput );
}

function blobToDataURL(blob, callback) {
	let a = new FileReader();
	a.onload = function(e) { callback(e.target.result) }
	a.readAsDataURL(blob);
}

function dataURLtoBlob(dataurl) {		// https://stackoverflow.com/questions/7845892/create-data-uris-on-the-fly
		let parts = dataurl.split(',');
		let mime = 'text/plain';
		if ( parts[0].match(/:(.*?);/) ) {
			mime = parts[0].match(/:(.*?);/)[1];
		} else {
			parts[1] = 'Error: Nothing to dataURLtoBlob';
			console.log('Nothing to dataURLtoBlob: '+dataurl);
		}
		if(parts[0].indexOf('base64') !== -1) {
			let bstr = atob(parts[1]), n = bstr.length, u8arr = new Uint8Array(n)
			while(n--){
				u8arr[n] = bstr.charCodeAt(n)
			}
			return new Blob([u8arr], {type:mime})
		} else {
			let raw = decodeURIComponent(parts[1])
			return new Blob([raw], {type: mime})
		}
	};

function getPosition ( element ) {
	let offsetLeft = 0, offsetTop = 0;
	do {
		offsetLeft += element.offsetLeft;
		offsetTop  += element.offsetTop;
		} while ( element = element.offsetParent );
	return [offsetLeft, offsetTop];
}

function getCoords(elem) {
	if ( elem.getBoundingClientRect ) {
		let box = elem.getBoundingClientRect();
		return {
				left: box.left + pageXOffset,
				top: box.top + pageYOffset
			};
	} else {
		let pos = getPosition(elem);
		return {
				left: pos[0],
				top: pos[1]
			};
	}
}

function elementInViewport(el,parent) {
	var top = el.offsetTop;
	var left = el.offsetLeft;
	var width = el.offsetWidth;
	var height = el.offsetHeight;

	var offY = window.pageYOffset;
	var offX = window.pageXOffset;
	var offH = window.innerHeight;
	var offW = window.innerWidth;

	while(el.offsetParent) {
		el = el.offsetParent;
		top += el.offsetTop;
		left += el.offsetLeft;
	}

	if (parent) {
		offY = parent.offsetTop
		offX = parent.offsetLeft;
		offH = parent.offsetHeight;
		offW = parent.offsetWidth;
	}
	return (
		top >= offY &&
		left >= offX &&
		(top + height) <= (offY + offH) &&
		(left + width) <= (offX + offW)
	);
}


document.addEventListener('DOMContentLoaded', function() {

		document.querySelectorAll('.closebox').forEach( b => {
				b.addEventListener('click', function(e) {
						let p = findParentBy(b, function(o) { return o.className.match(/\s*over\-panel/i) });
						p.style.display = 'none';
					});
			});

/* Drag element support */
		document.querySelectorAll('.dragbar').forEach( d => {
				let panel = findParentBy(d, function(n) { return n.className.match(/floatbar/i)} );
				if ( !panel ) panel = d;
				d.oncontextmenu = function(e) { e.preventDefault(); return false };
				d.onmousedown = function(e) {
						let pos = getCoords(panel);
						let shiftX = e.pageX - pos.left;
						let shiftY = e.pageY - pos.top;
						let dragStop = function() {
									d.onmouseup = null;
									document.removeEventListener('mousemove', dragTo);
									panel.className = panel.className.replace(/\s*drag/g,'');
							};
						let dragTo = function (e) {
								panel.style.left = e.pageX - shiftX + 'px';
								panel.style.top = e.pageY - shiftY + 'px';
								if ( e.buttons === 0 ) dragStop();
							};
						panel.className = panel.className.replace(/\s*drag/g,'');
						panel.className += ' drag';
						dragTo(e);
						document.addEventListener('mousemove', dragTo);
						d.onmouseup = dragStop;
					};
				d.onselectstart = function() { return false; };
				d.onselect = function() { return false; };
				d.ondragstart = function() { return false };
				panel.ondragstart = function() { return false };
			});
/* Drag element support END*/
	});

// Tab switching support
function tabSwitch(tab) {		// Tab switcher 
	if ( tab && tab.matches('.active') ) return false;
	let switcher = document.querySelector('#Tabs');
	if ( switcher.length == 0 ) return false;
	let page = document.location.pathname.split('/')[2] || document.location.pathname.split('/')[1];

	let cooks = getCookie('acTab');
	let def = {};
	if ( cooks ) def = JSON.parse(decodeURIComponent( cooks));

	if ( !def[page] ) def[page] = 0;
	let check = function(num) { return def[page] == num };
	let doClick = true;
	if ( tab ) {
		check = function(num) { return switcher.children[num].isSameNode(tab) };
		doClick = false;
	}
	for ( let num=0; num < switcher.children.length; num++ ) {
		if ( check(num) ) {
			switcher.children[num].className += ' active';
			document.getElementById('tab_'+num).className += ' shown';
			def[page] = num;
		} else {
			switcher.children[num].className = switcher.children[num].className.replace(/\s*active/ig,'');
			document.getElementById('tab_'+num).className = document.getElementById('tab_'+num).className.replace(/\s*shown/ig,'');
		}
	}

	if (switcher.children[def[page]].onclick && doClick ) switcher.children[def[page]].onclick();
	setCookie('acTab', encodeURIComponent(JSON.stringify(def)), 
						{ 'path':'/', 'domain':document.location.host,'max-age':60*60*24*365 } );
	if ( subSwitch ) subSwitch(tab);
	return false;
}

var uploaderObject = function(params) {
/*
 * Объект-загрузчик файла на сервер.
 * Передаваемые параметры:
 * file	   - объект File (обязателен)
 * url		- строка, указывает куда загружать (обязателен)
 * fieldName  - имя поля, содержащего файл (как если задать атрибут name тегу input)
 * onprogress - функция обратного вызова, вызывается при обновлении данных
 *			  о процессе загрузки, принимает один параметр: состояние загрузки (в процентах)
 * oncopmlete - функция обратного вызова, вызывается при завершении загрузки, принимает два параметра:
 *			  uploaded - содержит true, в случае успеха и false, если возникли какие-либо ошибки;
 *			  data - в случае успеха в него передается ответ сервера
 *			  
 *			  если в процессе загрузки возникли ошибки, то в свойство lastError объекта помещается
 *			  объект ошибки, содержащий два поля: code и text
 */

	if( !(params.file && params.url) ) {
		return false;
	}

	this.xhr = new XMLHttpRequest();
	this.reader = new FileReader();
	this.progress = 0;
	this.uploaded = false;
	this.successful = false;
	this.lastError = false;
	
	let self = this;	
	self.reader.onload = function() {
			self.xhr.upload.addEventListener("progress", function(e) {
				if (e.lengthComputable) {
					self.progress = (e.loaded * 100) / e.total;
					if(params.onprogress instanceof Function) {
						params.onprogress.call(self, Math.round(self.progress));
					}
				}
			}, false);

			self.xhr.upload.addEventListener("load", function(){
				self.progress = 100;
				self.uploaded = true;
			}, false);

			self.xhr.upload.addEventListener("error", function(){			
				self.lastError = {
					code: 1,
					text: 'Error uploading on server'
				};
			}, false);

			self.xhr.onreadystatechange = function () {
				let callbackDefined = params.oncomplete instanceof Function;
				if (this.readyState == 4) {
					if(this.status == 200) {
						if(!self.uploaded) {
							if(callbackDefined) {
								params.oncomplete.call(self, false);
							}
						} else {
							self.successful = true;
							if(callbackDefined) {
								params.oncomplete.call(self, true, this.responseText);
							}
						}
					} else {
						self.lastError = {
							code: this.status,
							text: 'HTTP response code is not OK ('+this.status+' - '+httpStatus[this.status]+')'
						};
						if(callbackDefined) {
							params.oncomplete.call(self, false);
						}
					}
				}
			};

			self.xhr.open("POST", params.url);

			let formData = new FormData();
			formData.append(params.fieldName, params.file, params.file.name);
			for ( let fld in params.formData ) {
				formData.append( fld, params.formData[fld] );
			};
			self.xhr.send(formData);
		};

	self.reader.readAsBinaryString(params.file);
};
