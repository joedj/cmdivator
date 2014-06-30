Cmdivator
---------

Cmdivator is an iOS tweak that extends [Activator](http://rpetrich.net/cydia/activator/) with the ability to run executable programs in response to events.

Users can add commands to `~/Library/Cmdivator/Cmds`

Cydia developers can depend on `net.joedj.cmdivator` and install commands to `/Library/Cmdivator/Cmds`

Cmdivator watches these directories, and automatically makes new commands available to Activator.

The following environment variables are exposed to commands:

* `ACTIVATOR_LISTENER_NAME`: The activator listener name, e.g. `net.joedj.cmdivator.listener:/Library/Cmdivator/Cmds/ReticulateSplines.cy`
* `ACTIVATOR_EVENT_NAME`: The activator event name, e.g. `libactivator.menu.press.triple`
* `ACTIVATOR_EVENT_MODE`: The activator event mode, i.e. `application` or `springboard` or `lockscreen`

[Cydia Depiction](http://moreinfo.thebigboss.org/moreinfo/depiction.php?file=cmdivatorDp)

<a href="https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=U7EU2XR2U2JMQ&lc=US&item_name=joedj&item_number=cmdivator&currency_code=USD&bn=PP%2dDonationsBF%3abtn_donate_SM%2egif%3aNonHosted">
  <img src="https://www.paypalobjects.com/en_US/i/btn/btn_donate_SM.gif" alt="Donate with PayPal">
</a>
