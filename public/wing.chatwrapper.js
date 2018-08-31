chatwrapper = {

    initialized : false,
    visible : false,
    labels: {
        icon : '<i class="fas fa-comments"></i>',
        open : 'Open Chat',
        close : 'Close Chat',
    },

    create_button() {
        const b = document.createElement('button');
        b.style.position = 'fixed';
        b.style.bottom = '0';
        b.id = 'chatwrapper_toggle';
        b.style.right = '10px';
        b.innerHTML = chatwrapper.labels.icon + ' ' + chatwrapper.labels.open;
        b.classList.add('btn');
        b.classList.add('btn-success');
        document.body.appendChild(b);
        return b;
    },

    attach(el) {
        el.addEventListener('click', chatwrapper.toggle);
        chatwrapper.button = el;
    },

    toggle() {
        if (!chatwrapper.initialized) {
            chatwrapper.initialize();
        }
        else if (chatwrapper.visible) {
            chatwrapper.hide();
        }
        else {
            chatwrapper.show();
        }
    },

    initialize() {
        chatwrapper.initialized = true;
        const m = document.createElement('div');
        m.style.position = 'fixed';
        m.style.bottom = '40px';
        m.style.right = '20px';
        m.style.width = localStorage.getItem('chatwrapper.width') || '95%';
        m.style.height = localStorage.getItem('chatwrapper.height') || '90%';
        m.style.zIndex = 99999999;
        m.id = 'chatwrapper_modal';
        m.style.boxShadow = '10px 20px 30px black';
        const nav = document.createElement('div');
        nav.style.position = 'absolute';
        nav.style.top = '0';
        nav.style.left = '0';
        nav.style.width = '100%';
        nav.style.height = '40px';
        nav.style.backgroundColor = 'grey';
        nav.style.color = 'white';
        m.appendChild(nav);
        const min = document.createElement('span');
        min.innerHTML = '&times;';
        min.style.paddingLeft = '10px';
        min.title = 'Minimize';
        min.addEventListener('click',chatwrapper.hide);
        nav.appendChild(min);
        const resize = document.createElement('span');
        resize.innerHTML = '&sdotb;';
        resize.style.paddingLeft = '10px';
        resize.title = 'Resize';
        resize.addEventListener('click',function() {
            if (m.style.width == '95%') {
                m.style.width = '50%';
                m.style.height = '45%';
            }
            else {
                m.style.width = '95%';
                m.style.height = '90%';
            }
            localStorage.setItem('chatwrapper.width', m.style.width);
            localStorage.setItem('chatwrapper.height', m.style.height);
        });
        nav.appendChild(resize);
        const oinw = document.createElement('span');
        oinw.innerHTML = '&boxbox;';
        oinw.style.paddingLeft = '10px';
        oinw.title = 'Open in new window';
        oinw.addEventListener('click',function() {
            window.open('/chat');
        });
        nav.appendChild(oinw);
        const i = document.createElement('iframe');
        i.src = '/chat';
        i.style.position = 'absolute';
        i.style.bottom = '0';
        i.style.left = '0';
        i.style.width = '100%';
        i.style.height = 'calc(100% - 30px)';
        i.style.border = '0';
        m.appendChild(i);
        document.body.appendChild(m);
        chatwrapper.modal = m;
        chatwrapper.iframe = i;
        chatwrapper.show();
    },

    show() {
        chatwrapper.visible = true;
        chatwrapper.button.innerHTML = chatwrapper.labels.icon + ' ' + chatwrapper.labels.close;
        chatwrapper.modal.style.visibility = "visible";
    },

    hide() {
        chatwrapper.visible = false;
        chatwrapper.button.innerHTML = chatwrapper.labels.icon + ' ' + chatwrapper.labels.open;
        chatwrapper.modal.style.visibility = "hidden";
    },

};
