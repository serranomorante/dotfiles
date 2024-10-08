# keyd setup

Guides related to my keyd setup.

## Latin chars with keyd

> This guide is specific to xorg only

Before discovering [keyd](https://github.com/rvaiya/keyd) I had to constantly switch between **english** and **spanish** layouts in order for me to write words like `mañana` but at the same time use chars like `<>|~`... this was a very painful workflow.

Now instead of switching between language layouts I just map all these special characters (`á`, `é`, `í`, `ó`, `ú`, `ñ`) to a `<modifier>+<letter>` combination. For example, pressing `alt+a` writes `á`. This is far more quickly and pleasant than having to switch layouts and then remember to switch then back.

### Process to map new chars

My process to map new chars is as follows:

1. First on `/etc/keyd/default.conf` I add the new special char that I want to use:

```dotini
[ids]

*

[main]

leftalt = layer(spanish)

[spanish:A]

# Map a to á
a = á

...

# Map n to ñ
n = ñ

[spanish+shift]

# Map a to Á
a = Á

...

# Map n to Ñ
n = Ñ
```

2. That's not all, you need to find a keyd-specific XKB sequence string for your char (`á`, `ñ`, etc...) from here: `/usr/share/keyd/keyd.compose` and then copy it to your `.XCompose` file, usually in `~/.XCompose` or create a new one if it doesn't exists.

**Example**

> Find and copy your char from the `/usr/share/keyd/keyd.compose` file (that file is automatically generated by `keyd` upon installation):

```dotini
...
<Cancel> <0> <1> <1> : "¥"
<Cancel> <0> <1> <2> : "¦"
<Cancel> <0> <1> <3> : "§"
<Cancel> <0> <1> <4> : "¨"
<Cancel> <0> <1> <5> : "©"
<Cancel> <0> <1> <6> : "ª"
<Cancel> <0> <1> <7> : "«"
<Cancel> <0> <1> <8> : "¬"
<Cancel> <0> <1> <9> : "­"
<Cancel> <0> <1> <a> : "®"
<Cancel> <0> <2> <p> : "á" <- copy this
<Cancel> <0> <3> <5> : "ñ" <- copy this
<Cancel> <0> <1> <t> : "Á" <- copy this
<Cancel> <0> <2> <9> : "Ñ" <- copy this
...
```

3. Paste your keyd-specific XKB sequence string on your `~/.XCompose` file like this:

```dotini
<Cancel> <0> <2> <p> : "á"
<Cancel> <0> <3> <5> : "ñ"
<Cancel> <0> <1> <t> : "Á"
<Cancel> <0> <2> <9> : "Ñ"
```

4. Finally you must logout and login again so the `~/.XCompose` can be re-executed by your system again.

### Important

Even thought the `man keyd` page recommends this:

>    Unicode Support
       If keyd encounters a valid UTF8 sequence as a right hand value, it will try and translate that sequence into a macro which emits a keyd-specific XKB sequence.
       In order for this to work, the sequences defined in the compose file shipped with keyd (/usr/share/keyd/keyd.compose) must be accessible. This can be achieved globally by copying the file to the appropriate location in
       /usr/share/X11/locale, or on a per-user basis by symlinking it to ˜/.XCompose.
       E.g.
           ln -s /usr/share/keyd/keyd.compose ˜/.XCompose
       Additionally  you will need to be using the default US layout on your display server. Users of non-english layouts are advised to set their layout within keyd (see Layouts) to avoid conflicts between the display server
       layout and keyd's unicode functionality.
       Note: You may have to restart your applications for this to take effect.
       Note 2: The generated compose sequences are affected by modifiers in the normal way. If you want shift to produce a different symbol, you will need to define a custom shift layer (see the included layout files  for  an
       example).

That was actually a pretty bad idea for me because my `i3` keymaps (and the whole i3 app) stopped working so that's why I don't symlink the whole `keyd.compose` file and instead just copy the lines that I need from it.
