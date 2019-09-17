DGSLib
======

This library implements a client to play on
<https://www.dragongoserver.net> (DGS). The client knows how
to log in, retrieve the list of games to be played, retrieve
board positions, play moves and sometimes finish games.
It uses the QuickSuite API, which is thoroughly documented
in DGS sourcecode <https://sourceforge.net/p/dragongoserver/dgs-main/ci/master/tree/specs/quick_suite.txt>.

A Robot object is also provided, which makes it trivial to
interface a GTP Go program to DGS.

GnuGo is used to evaluate the status of stones at the end.
If GnuGo and DGS agree on dead stones, then the robot will
terminate the game automatically. Otherwise, it will set the
board aside, and the game will need to be finished manually.


The library isn't really documented yet.  The easiest way to
get acquinted with the code is probably to start with the
example bots.

Implementing a Robot
====================

The library implements an object DGSBot, which does
everything. A typical bot program is reduced to creating a
bot object, configuring it, then running it.

Two examples are included: `qrobot`, which runs GnuGo, and
`mogobot`, which runs Mogo.

The `do_everything` method will connect, process all game
challenges, play one move on each pending game, try to
finish games if needed, then return.

Some notes about the various fields that can be set in the
bot:

* sgffile, sgfout: These are filenames used to temporarily
  store SGF files. If you are running several bots on the same
  machine (or on the same NFS shares), make sure these are
  unique. This caveat applies to all filenames.

* finished_games: this is a file of games that the bot
  considers finished. This is used to skip games that are
  finished but where DGS and GnuGo disagree on the status of
  stones. This is for performance only, so that the bot
  doesn't fetch boards it doesn't need. If you erase that
  file, the bot will just fetch the boards, try to finish
  them, fail, and fill the file again.

* error_games: a list of games that produced an error. The
  behaviour is the same as the previous setting.

* gtp_engine: Specifies the executable to be run. It is
  expected to accept GTP commands on stdin, and reply GTP on
  stdout.

* board_ok: This is a Perl reference. Whenever someone
  challenges the bot, it'll automatically accept the
  challenge if this callback returns true. The callback
  receives a DGSMessage as parameter, initialised with the
  challenge settings. This makes it easy to make the bot
  refuse all challenges ('return 0'), accept all challenges,
  or accept only certain kind of games. For example, GnuGo
  plays like crap at sizes below 13 and can't play above 19,
  and Mogo can only play specific sizes and handicap below 4.

* badsize_msg: This is slightly mis-named. This is a string
  which will be included in messages when refusing a
  challenge. It should explain what restrictions apply.

* pre_run: This is a Perl reference to a function that
  receives a GTP object initialised with the GTP agent, and
  the board on which we play. It is called after the GTP
  program has been started and the SGF loaded, and before the
  move is computed. This can be used to fine-tune the agent by
  sending additional GTP commands (see mogobot for komi hacking).

Installation
============

The only exotic module used is Games::Go::SGF, available
from CPAN.


The bot needs to be run repeatedly. This can be done with a
simple shell loop, or a crontab, for example:

        * * * * * cd $HOME/dgs ;  nice -n 17 ./robot 

The bot code checks that it's not running already, so
running it again when it hasn't finished the previous round
is not a problem.

Happy go-ing!
