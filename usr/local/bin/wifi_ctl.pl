#!/usr/bin/perl
use strict;
use warnings;
use Gtk3 '-init';
use IPC::Open2;

use Data::Dumper;

my $wpa_cli = "/sbin/wpa_cli";

my %networks;

# Создание основного окна
my $window = Gtk3::Window->new('toplevel');
$window->set_title("Wi-Fi Manager");
$window->set_default_size(400, 400);
$window->signal_connect(delete_event => sub { Gtk3->main_quit; });

# Создание списка интерфейсов (A)
my $store_A = Gtk3::ListStore->new('Glib::String');
my $list_A = Gtk3::TreeView->new($store_A);
my $colA1 = Gtk3::TreeViewColumn->new_with_attributes('Interface', Gtk3::CellRendererText->new, text => 0);
$list_A->append_column($colA1);

# Создание списка сетей (B)
my $store_B = Gtk3::ListStore->new('Glib::String','Glib::String','Glib::String');
my $list_B = Gtk3::TreeView->new($store_B);
my $colB1 = Gtk3::TreeViewColumn->new_with_attributes('#', Gtk3::CellRendererText->new, text => 0);
my $colB2 = Gtk3::TreeViewColumn->new_with_attributes('SSID', Gtk3::CellRendererText->new, text => 1);
my $colB3 = Gtk3::TreeViewColumn->new_with_attributes('Status', Gtk3::CellRendererText->new, text => 2);
$list_B->append_column($colB1);
$list_B->append_column($colB2);
$list_B->append_column($colB3);

# Кнопки управления
my $scan_button = Gtk3::Button->new_with_label("Add network");
my $select_button = Gtk3::Button->new_with_label("Select");
my $delete_button = Gtk3::Button->new_with_label("Remove");
my $quit_button = Gtk3::Button->new_with_label("Quit");
$_->set_sensitive(0) for ($scan_button, $select_button, $delete_button);

# Формирование окна
{
  my $vbox = Gtk3::Box->new('vertical', 5);
  $window->add($vbox);

  $vbox->pack_start($list_A, 1, 1, 5);
  $vbox->pack_start($list_B, 1, 1, 5);

  my $button_box = Gtk3::ButtonBox->new('horizontal');
  $button_box->pack_start($_, 1, 1, 5) for ($scan_button, $select_button, $delete_button, $quit_button);
  $vbox->pack_start($button_box, 1, 1, 20);
}

# =========================================
# Функция для выполнения команд wpa_cli
sub run_wpa_cli {
  my ($cmd) = @_; 
  print STDERR "cmd: ==$cmd==\n";
  open2(my $out, my $in, "$wpa_cli $cmd");
  my @result = <$out>;
  print STDERR Dumper(@result);
  return @result;
}

# Заполнение списка интерфейсов (A)
sub load_interfaces {
  $list_A->get_model->clear;
  my @interfaces = run_wpa_cli('interface');
  foreach my $iface (@interfaces) {
    next if($iface =~ /\w+\s+\w/);
    $iface =~ s/\s+$//;
    my $iter = $list_A->get_model->append();
    $list_A->get_model->set($iter, 0 => $iface);
  }
}

# Получение выбранного интерфейса
sub get_selected_iface {
  my $selection = $list_A->get_selection;
  my ($model, $iter) = $selection->get_selected;
  return $model->get($iter, 0);
}

# Получение выбранной сети
sub get_selected_network {
  my $selection = $list_B->get_selection;
  my ($model, $iter) = $selection->get_selected;
  return $model->get($iter, 0);
}

# Заполнение списка сетей (B) для выбранного интерфейса
sub load_networks {
  my ($iface) = @_;
  $list_B->get_model->clear;
  my @networks = run_wpa_cli("-i $iface list_network");
  shift @networks; 
  foreach my $net (@networks) {
    my ($id, $ssid, $bssid, $flags) = split(/\s/, $net);
    my $iter = $list_B->get_model->append();
    $list_B->get_model->set($iter, 0 => $id, 1 => $ssid, 2 => $flags);
    $networks{$ssid} = $id;
  }
  $select_button->set_sensitive(0);
  $delete_button->set_sensitive(0);
}

# Выбор сети
sub select_network {
  my $iface = get_selected_iface();
  my $id = get_selected_network();
  run_wpa_cli("-i $iface select_network $id");
  run_wpa_cli("-i $iface save_config");
  load_networks($iface);
}

# Удаление сети
sub delete_network {
  my $iface = get_selected_iface();
  my $id = get_selected_network();
  run_wpa_cli("-i $iface remove_network $id");
  run_wpa_cli("-i $iface save_config");
  %networks=();
  load_networks($iface);
}

# Ввод пароля
sub show_password_dialog {
  my ($iface, $ssid, $parent_window) = @_;

  my $dialog = Gtk3::Dialog->new("Password", $parent_window,
    [ 'modal' ], 'gtk-ok', 'accept', 'gtk-cancel', 'cancel');
  $dialog->set_default_size(300, 100);

  my $entry = Gtk3::Entry->new();
  $entry->set_visibility(0);
  $dialog->get_content_area()->pack_start($entry, 1, 1, 5);

  $dialog->signal_connect(response => sub {
    my ($dialog, $response) = @_;
    if ($response eq 'accept') {
      my $pass= $entry->get_text();
      if ($pass) {
        my $id = $networks{ $ssid };
        if(!defined $id){
          my @output = run_wpa_cli("-i $iface add_network");
          if(defined $output[0] && $output[0] =~ /(\d+)/){
            $id = $1;
          }
          else{
            $dialog->destroy;
            return;
          }
        }
        run_wpa_cli("-i $iface set_network $id ssid '\"$ssid\"'");
        run_wpa_cli("-i $iface set_network $id psk '\"$pass\"'");
        run_wpa_cli("-i $iface enable_network $id");
        run_wpa_cli("-i $iface save_config");
        sleep(1);
      }
    }
    load_networks($iface);
    $dialog->destroy;
    $parent_window->destroy;
  });

  $dialog->show_all;
}

# Выбор сетей из отсканированных
sub scan_networks {
  my $iface = get_selected_iface();
  return unless $iface;

  # Создаем новое окно сканирования
  my $scan_window = Gtk3::Dialog->new(
    "Scan Wi-Fi",
    $window, 
    [ 'modal' ]
  );
  $scan_window->set_default_size(400, 300);

  my $vbox_scan = Gtk3::Box->new('vertical', 5);
  my $content_area = $scan_window->get_content_area();
  $content_area->add($vbox_scan);

  my $scrolled_window = Gtk3::ScrolledWindow->new();
  $scrolled_window->set_policy('automatic', 'automatic');
  $scrolled_window->set_min_content_height(400);

  # Список доступных сетей (C)
  my $store_C = Gtk3::ListStore->new('Glib::String','Glib::String');
  my $list_C = Gtk3::TreeView->new($store_C);
  $scrolled_window->add($list_C);
  $vbox_scan->pack_start($scrolled_window, 1, 1, 5);

  my $colC1 = Gtk3::TreeViewColumn->new_with_attributes('SSID', Gtk3::CellRendererText->new, text => 0);
  my $colC2 = Gtk3::TreeViewColumn->new_with_attributes(' ', Gtk3::CellRendererText->new, text => 1);
  $list_C->append_column($colC1);
  $list_C->append_column($colC2);

  # Кнопки
  my $start_button = Gtk3::Button->new_with_label("Scan");
  my $close_button = Gtk3::Button->new_with_label("Close");

  my $button_box = Gtk3::ButtonBox->new('horizontal');
  $button_box->pack_start($_, 1, 1, 5) for ($start_button, $close_button);
  $vbox_scan->pack_start($button_box, 1, 1, 5);

  $scan_window->show_all;

  run_wpa_cli("-i $iface scan");
  sleep(1);

  # -------------------------------------------
  # Обработчик выбора сети в списке C (делает кнопку "Добавить" активной)
  my $selection_C = $list_C->get_selection;
  $selection_C->signal_connect(changed => sub {
    my ($model, $iter) = $selection_C->get_selected;
    my $sel_ssid = $list_C->get_model->get($iter, 0);
    my $iface = get_selected_iface();
    
    show_password_dialog($iface, $sel_ssid, $scan_window);

  });

  # -------------------------------------------
  $start_button->signal_connect(clicked => sub {
    my %scan_results;
    $list_C->get_model->clear;
  
    my @results = run_wpa_cli("-i $iface scan_results");
    shift @results;

    my $list = {};

    foreach my $line (@results) {
      $line =~ s/[\n\r]+//gm;
      print STDERR "$line\n";
      my ($bssid, $freq, $signal, $flags, $ssid) = split(/\s+/, $line, 5);
      next unless $ssid;

      $list->{$ssid} = 1;
    }

    foreach my $ssid (keys(%$list)){
      my $iter = $list_C->get_model->append();
      my $fl = (defined $networks{ $ssid }) ? '*':'';
      $list_C->get_model->set($iter, 0 => $ssid, 1 => $fl);
    }
  });

  # -------------------------------------------
  # Закрытие окна
  $close_button->signal_connect(clicked => sub {
    $scan_window->destroy;
  });

}

# =========================================

my $selection_A = $list_A->get_selection;
$selection_A->signal_connect(changed => sub {
  my $iface = get_selected_iface();
  if ($iface) {
    %networks=();
    load_networks($iface);
    $scan_button->set_sensitive(1);
  }
});

my $selection_B = $list_B->get_selection;
$selection_B->signal_connect(changed => sub {
  $select_button->set_sensitive(1);
  $delete_button->set_sensitive(1);
});

$scan_button->signal_connect('clicked',sub {
  scan_networks();
});

$select_button->signal_connect('clicked',sub {
  select_network();
});

$delete_button->signal_connect('clicked',sub {
  delete_network();
});

$quit_button->signal_connect(clicked => sub {
  Gtk3->main_quit;
});

#########################################################
# Загрузка интерфейсов при старте
load_interfaces();

$window->show_all;
Gtk3->main;

