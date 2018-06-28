SVN/Notify version 2.87
=======================

This class may be used for sending email messages for
[Subversion](http://subversion.tigris.org/) repository activity. There are a
number of different modes supported, and SVN::Notify is fully subclassable, to
easily add new functionality. By default, a list of all the files affected by
the commit will be assembled and listed in a single message. An additional
option allows diffs to be calculated for the changes and either appended to
the message or added as an attachment. The included subclass,
SVN::Notify::HTML, allows the messages to be sent in HTML format.

Installation
------------

To install this module, type the following:

    perl Build.PL
    ./Build
    ./Build test
    ./Build install

Or, if you don't have Module::Build installed, type the following:

    perl Makefile.PL
    make
    make test
    make install

Dependencies
------------

SVN::Notify has the following dependencies:

* Getopt::Long
  This module is included with Perl.

* Pod::Usage
  For calling 'svnnotify' with the --help or --man options, or when it fails
  to process the command-line options, usage output will be triggered by
  Pod::Usage, has been included with Perl since 5.6.0.

* HTML::Entities
  This module is required for sending HTML-formatted notifications with
  SVN::Notify::HTML.

* Net::SMTP
  This module is required for sending notification messages via SMTP rather
  than by sendmail (e.g., under Windows). That is, it is required when using
  the --smtp option.

* Net::SMTP_auth
  This module is required for sending notifications messages via an
  authenticating SMTP server, i.e., when using the --smtp-authtype option.

Copyright and License
---------------------

Copyright (c) 2004-2018 David E. Wheeler. Some Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
