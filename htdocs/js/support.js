var d = document;
var ontime;
var djson;

const mimeTypes = {'ttf':'application/x-font-ttf', 'ttc':'application/x-font-ttf', 'otf':'application/x-font-opentype', 
				'woff':'application/font-woff', 'woff2':'application/font-woff2', 'svg':'image/svg+xml',
				'sfnt':'application/font-sfnt', 'eot':'application/vnd.ms-fontobject' ,
				'tif':'image/tiff', 'tiff':'image/tiff', 'bmp':'image/x-ms-bmp',
				'jpg':'image/jpeg', 'jpeg':'image/jpeg', 'jpe':'image/jpeg', 'png':'image/png', 'gif':'image/gif',
				'zip':'application/zip', 
				};

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
					console.log(this.response.text);
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
};

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
