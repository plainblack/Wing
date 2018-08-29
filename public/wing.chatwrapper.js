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
        const i = document.createElement('iframe');
        i.src = '/chat';
        i.style.position = 'fixed';
        i.style.bottom = '40px';
        i.style.right = '20px';
        i.style.width = '95%';
        i.style.height = '90%';
        i.style.zIndex = 99999999;
        i.id = 'chatwrapper_window';
        i.style.boxShadow = '10px 20px 30px black';
        document.body.appendChild(i);
        chatwrapper.iframe = i;
        chatwrapper.show();
    },

    show() {
        chatwrapper.visible = true;
        chatwrapper.button.innerHTML = chatwrapper.labels.icon + ' ' + chatwrapper.labels.close;
        chatwrapper.iframe.style.visibility = "visible";
    },

    hide() {
        chatwrapper.visible = false;
        chatwrapper.button.innerHTML = chatwrapper.labels.icon + ' ' + chatwrapper.labels.open;
        chatwrapper.iframe.style.visibility = "hidden";
    },

};
