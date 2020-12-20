unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ComCtrls, Spin, ExtCtrls, synaser, dateutils, inifiles;

type

  { TForm1 }

  TForm1 = class(TForm)
    Button1: TButton;
    Button2: TButton;
    FSE1: TFloatSpinEdit;
    Image1: TImage;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Memo1: TMemo;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private

  public


  end;

var
  Form1: TForm1;
  COM_PORT: string;
  CONFIG_FILE: string;
  transkill: boolean;

implementation

{$R *.lfm}


// FONCTION RECUPERATION PARAMETRE DANS FICHIER INI
function getiniparam(conf, sect, param: string): string;
var
  inif: tinifile;
begin
  if (conf = '') or (not Fileexists(conf)) then
    exit;
  inif := tinifile.Create(conf);
  Result := inif.ReadString(sect, param, '');
  inif.Free;
end;

// Conversion chr -> string
function GetCmdStrByChr(c: char): string;
begin
  Result := c;
  case Ord(c) of
    2: Result := 'STX';
    3: Result := 'ETX';
    4: Result := 'EOT';
    5: Result := 'ENQ';
    6: Result := 'ACK';
    15: Result := 'NAKX';
    21: Result := 'NAK';
    20: Result := 'SPC';
  end;
end;

//Affichage dans un memo
procedure log(a: string);
var
  i: integer;
var
  retchaineord: string;
begin

  retchaineord := '';
  for i := 1 to length(a) do
    retchaineord := retchaineord + GetCmdStrByChr(a[i]);
  form1.memo1.Lines.add(retchaineord);
end;

// Fonction d'envoi du montant (seconde version)
function Envoi_v2(montant: double; port: string): boolean;
var
  LRC: integer;
  j: integer;
  SEnvoiParam: string;
  sEnvoi: string;
  SerialCB: TBlockserial;
  montantstr: string;
  RetChaine: string;
  canfollow: boolean;
const
  A_OK = '0';
  A_NOK = '7';
  A_STX = chr(2);
  A_ETX = chr(3);
  A_EOT = chr(4);
  A_ENQ = chr(5);
  A_ACK = chr(6);
  A_NAK = chr(15);
  A_SPC = chr(20);

  procedure sendStringandLog(a: string);
  begin
    SerialCB.SendString(a);
    log('>' + a);
  end;

  function recvPacketandLog(t: integer): ansistring;
  begin
    Result := SerialCB.RecvPacket(t);
    log('<' + Result);
  end;

  // Fonction d'envoi des données et attente retour du/sur le TPE
  function Envoi_donnees(Data: string; timeout: integer = 5000): boolean;
  var
    a, b: TdateTime;
    t_out: boolean;
    retchr: char;
  begin
    Canfollow := False;
    with SerialCB do
    begin
      SendStringandlog(Data);
      a := now;
      repeat
        b := now;
        sleep(50);
        application.ProcessMessages;
        if WaitingData > 0 then
        begin
          Retchaine := RecvPacketandLog(150);
          retchr := Retchaine[1];
          case retchr of
            A_ENQ: SendStringAndLog(A_ACK);
            A_ACK: canfollow := True;
            A_EOT: canfollow := True;
            A_STX:
              case RetChaine[4] of
                A_OK: Log('Transaction acceptée');
                A_NOK: Log('Transaction annulée');
              end;
            A_NAK: Log('Refus du terminal');
          end;
        end;
        t_out := millisecondsbetween(a, b) >= timeout;
        if timeout = -1 then
          t_out := False;
      until (transkill) or (t_out) or (canfollow);
      if transkill then
        log('Transaction annulée par l''utilisateur');
      if (t_out) then
      begin
        log('Délai dépassé');
        exit;
      end;
      Result := Canfollow;
    end;
  end;

begin
  SerialCB := TBlockserial.Create;
  Result := False;
  try
    with SerialCB do
    begin
      RaiseExcept := False;
      Connect(port);
      Config(9600, 8, 'N', SB1, False, False);
      RTS := False;
      DTR := False;
      if LastError <> 0 then
      begin
        ShowMessage('Communication avec le terminal CB impossible');
        exit;
      end;
      montantstr := (IntToStr(round(montant * 100)));
      if length(montantstr) < 8 then
        for j := 1 to 8 - (length(montantstr)) do
          montantstr := ('0') + montantstr;
      // CHAINE A ENVOYER
      sEnvoi := ('01') + montantstr + ('010978          ') + A_ETX;
      // CALCUL LRC
      LRC := 0;
      for j := 1 to length(sEnvoi) do
        LRC := LRC xor Ord(sEnvoi[j]);
      // PHASE 1 : COMMUNICATION AVEC LE TPE
      sEnvoiParam := A_ENQ;
      if not Envoi_donnees(sEnvoiParam, 2000) then
        exit;
      //PHASE 2 : ENVOI DONNEES
      sEnvoiParam := A_STX + SEnvoi + chr(LRC);
      if not Envoi_donnees(sEnvoiParam, 2000) then
        exit;
      //PHASE 3 : FINALISATION
      sEnvoiParam := A_EOT;
      if not Envoi_donnees(sEnvoiParam, -1) then
        exit;
      Result := True;
    end
  finally
    SerialCB.Free;
  end;
end;


{ TForm1 }

procedure TForm1.Button1Click(Sender: TObject);
begin
  transkill := False;
  if Envoi_v2(FSE1.Value, COM_PORT) then
    FSE1.Value := 0;
end;

procedure TForm1.Button2Click(Sender: TObject);
begin
  transkill := True;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  CONFIG_FILE := extractfilepath(ParamStr(0)) + 'params.ini';
  if not fileexists(CONFIG_FILE) then
  begin
    ShowMessage('Le fichier de configuration est absent, impossible de continuer');
    Application.Terminate;
  end;
  COM_PORT := Getiniparam(CONFIG_FILE, 'PARAMS', 'COM_PORT');
end;

end.
