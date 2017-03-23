# Babylon mode _(babylon-mode)_

> An emacs mode for highlighting JavaScript using the babylon parser

Instead of trying to re-implement a JS parser in elisp like js2-mode, or trying
to parse JS and JSX using regexes like web-mode, we try to offload a bunch of
the actual parsing work onto some code that we know actually works:
[babylon](https://github.com/babel/babylon). Babylon is the parser that babel
uses, so we can be very confident that it will successfully parse any
JavaScript we throw at it! All we need to do is traverse the tree, highlight
things that we want, and we're good to go.

Currently, this comes at the significant downside that it is painfully slow and
very error-prone. But I'm working on it, and hopefully it will get to the point
that it will be useful for other people.

## Install

Clone this repo somewhere
```shell
% git clone https://github.com/xymostech/babylon-mode.git
```

Add the path to `load-path` in your .emacs.el:
```elisp
(add-to-list 'load-path "/path/to/babylon-mode")
```

Then, add an autoload for loading babylon-mode, and optionally add babylon-mode
to `auto-mode-alist`:

```elisp
(autoload 'babylon-mode "babylon-mode" nil t)

(add-to-list 'auto-mode-alist '("\\.jsx$" . babylon-mode))
(add-to-list 'auto-mode-alist '("\\.js$" . babylon-mode))
```

## Usage

Visit a .js or .jsx file, or manually run `babylon-mode`:
```
babylon-mode
```

## Maintainer

- xymostech

## Contribute

This is the first large amount of elisp that I've written (aside from my
.emacs.el), so I apologize for any elisp faux pas I have committed. If you find
this useful and have any ideas for improvement, I'd love to hear! Issues
pointing out how broken things currently are are probably not useful, because
the whole thing is pretty broken.

In other words:
 - Ask questions in github issues
 - PRs are welcome, especially to improve the elisp, but huge code refactorings
   are not useful. I'm trying to learn elisp and continue working on this, so
   huge changes would put a damper on it.

## License

[MIT](LICENSE)
