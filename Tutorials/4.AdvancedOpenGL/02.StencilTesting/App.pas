unit App;

{$INCLUDE 'Sample.inc'}

interface

uses
  System.Classes,
  System.UITypes,
  System.SysUtils,
  {$INCLUDE 'OpenGL.inc'}
  Sample.Classes,
  Sample.Common,
  Sample.App;

type
  TStencilTestingApp = class(TApplication)
  private
    FCamera: ICamera;
    FShader: IShader;
    FShaderSingleColor: IShader;
    FCubeVAO: IVertexArray;
    FPlaneVAO: IVertexArray;
    FUniformMVP: TUniformMVP;
    FUniformMVPSingleColor: TUniformMVP;
    FUniformTexture1: GLint;
    FCubeTexture: GLuint;
    FFloorTexture: GLuint;
  public
    procedure Initialize; override;
    procedure Update(const ADeltaTimeSec, ATotalTimeSec: Double); override;
    procedure Shutdown; override;
    procedure Resize(const AWidth, AHeight: Integer); override;
    function NeedStencilBuffer: Boolean; override;
  public
    procedure KeyDown(const AKey: Integer; const AShift: TShiftState); override;
    procedure KeyUp(const AKey: Integer; const AShift: TShiftState); override;
    procedure MouseDown(const AButton: TMouseButton; const AShift: TShiftState;
      const AX, AY: Single); override;
    procedure MouseMove(const AShift: TShiftState; const AX, AY: Single); override;
    procedure MouseUp(const AButton: TMouseButton; const AShift: TShiftState;
      const AX, AY: Single); override;
    procedure MouseWheel(const AShift: TShiftState; const AWheelDelta: Integer); override;
  end;

implementation

uses
  Neslib.FastMath;

const
  { Each cube vertex consists of a 3-element position and 2-element texture coordinate.
    Each group of 4 vertices defines a side of a cube. }
  CUBE_VERTICES: array [0..119] of Single = (
    // Positions       // Texture Coords
    -0.5, -0.5, -0.5,  0.0, 0.0,
     0.5, -0.5, -0.5,  1.0, 0.0,
     0.5,  0.5, -0.5,  1.0, 1.0,
    -0.5,  0.5, -0.5,  0.0, 1.0,

    -0.5, -0.5,  0.5,  0.0, 0.0,
     0.5, -0.5,  0.5,  1.0, 0.0,
     0.5,  0.5,  0.5,  1.0, 1.0,
    -0.5,  0.5,  0.5,  0.0, 1.0,

    -0.5,  0.5,  0.5,  1.0, 0.0,
    -0.5,  0.5, -0.5,  1.0, 1.0,
    -0.5, -0.5, -0.5,  0.0, 1.0,
    -0.5, -0.5,  0.5,  0.0, 0.0,

     0.5,  0.5,  0.5,  1.0, 0.0,
     0.5,  0.5, -0.5,  1.0, 1.0,
     0.5, -0.5, -0.5,  0.0, 1.0,
     0.5, -0.5,  0.5,  0.0, 0.0,

    -0.5, -0.5, -0.5,  0.0, 1.0,
     0.5, -0.5, -0.5,  1.0, 1.0,
     0.5, -0.5,  0.5,  1.0, 0.0,
    -0.5, -0.5,  0.5,  0.0, 0.0,

    -0.5,  0.5, -0.5,  0.0, 1.0,
     0.5,  0.5, -0.5,  1.0, 1.0,
     0.5,  0.5,  0.5,  1.0, 0.0,
    -0.5,  0.5,  0.5,  0.0, 0.0);

const
  { The indices define 2 triangles per cube face, 6 faces total }
  CUBE_INDICES: array [0..35] of UInt16 = (
     0,  1,  2,   2,  3,  0,
     4,  5,  6,   6,  7,  4,
     8,  9, 10,  10, 11,  8,
    12, 13, 14,  14, 15, 12,
    16, 17, 18,  18, 19, 16,
    20, 21, 22,  22, 23, 20);

const
  { Each plane vertex consists of a 3-element position and 2-element texture
    coordinate.
    Note: note we set the texture coordinates higher than 1 that together with
    GL_REPEAT (as texture wrapping mode) will cause the floor texture to
    repeat. }
  PLANE_VERTICES: array [0..19] of Single = (
    // Positions       // Texture Coords
     5.0, -0.5,  5.0,  2.0, 1.0,
    -5.0, -0.5,  5.0,  0.0, 0.0,
    -5.0, -0.5, -5.0,  0.0, 2.0,
     5.0, -0.5, -5.0,  2.0, 2.0);

const
  PLANE_INDICES: array [0..5] of UInt16 = (0, 1, 2, 0, 2, 3);

{ TStencilTestingApp }

procedure TStencilTestingApp.Initialize;
var
  VertexLayout: TVertexLayout;
begin
  { Initialize the asset manager }
  TAssets.Initialize;

  { Setup some OpenGL options }
  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_LESS);
  glEnable(GL_STENCIL_TEST);
  glStencilFunc(GL_NOTEQUAL, 1, $FF);
  glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);

  { Create camera }
  FCamera := TCamera.Create(Width, Height, Vector3(0, 0, 3));

  { Build and compile our shader program }
  FShader := TShader.Create('shaders/stencil_testing.vs', 'shaders/stencil_testing.fs');
  FUniformMVP.Init(FShader);
  FUniformTexture1 := FShader.GetUniformLocation('texture1');

  FShaderSingleColor := TShader.Create('shaders/stencil_testing.vs', 'shaders/stencil_single_color.fs');
  FUniformMVPSingleColor.Init(FShaderSingleColor);

  { Define layout of the attributes in the shader }
  VertexLayout.Start(FShader)
    .Add('position', 3)
    .Add('texCoords', 2);

  { Create the vertex array for the cube. }
  FCubeVAO := TVertexArray.Create(VertexLayout,
    CUBE_VERTICES, SizeOf(CUBE_VERTICES), CUBE_INDICES);

  { Create the vertex array for the plane.
    It uses the same vertex layout as the cube. }
  FPlaneVAO := TVertexArray.Create(VertexLayout,
    PLANE_VERTICES, SizeOf(PLANE_VERTICES), PLANE_INDICES);

  { Load textures }
  FCubeTexture := LoadTexture('textures/marble.jpg');
  FFloorTexture := LoadTexture('textures/metal.png');
end;

procedure TStencilTestingApp.KeyDown(const AKey: Integer; const AShift: TShiftState);
begin
  if (AKey = vkEscape) then
    { Terminate app when Esc key is pressed }
    Terminate
  else
    FCamera.ProcessKeyDown(AKey);
end;

procedure TStencilTestingApp.KeyUp(const AKey: Integer; const AShift: TShiftState);
begin
  FCamera.ProcessKeyUp(AKey);
end;

procedure TStencilTestingApp.MouseDown(const AButton: TMouseButton;
  const AShift: TShiftState; const AX, AY: Single);
begin
  FCamera.ProcessMouseDown(AX, AY);
end;

procedure TStencilTestingApp.MouseMove(const AShift: TShiftState; const AX, AY: Single);
begin
  FCamera.ProcessMouseMove(AX, AY);
end;

procedure TStencilTestingApp.MouseUp(const AButton: TMouseButton;
  const AShift: TShiftState; const AX, AY: Single);
begin
  FCamera.ProcessMouseUp;
end;

procedure TStencilTestingApp.MouseWheel(const AShift: TShiftState;
  const AWheelDelta: Integer);
begin
  FCamera.ProcessMouseWheel(AWheelDelta);
end;

function TStencilTestingApp.NeedStencilBuffer: Boolean;
begin
  Result := True;
end;

procedure TStencilTestingApp.Resize(const AWidth, AHeight: Integer);
begin
  inherited;
  if Assigned(FCamera) then
    FCamera.ViewResized(AWidth, AHeight);
end;

procedure TStencilTestingApp.Shutdown;
begin
  glDeleteTextures(1, @FCubeTexture);
  glDeleteTextures(1, @FFloorTexture);
end;

procedure TStencilTestingApp.Update(const ADeltaTimeSec, ATotalTimeSec: Double);
const
  SCALE_FACTOR = 1.1;
var
  Model, View, Projection, Translate, Scale: TMatrix4;
begin
  FCamera.HandleInput(ADeltaTimeSec);

  { Define the viewport dimensions }
  glViewport(0, 0, Width, Height);

  { Clear the color and depth buffer }
  glClearColor(0.1, 0.1, 0.1, 1.0);
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT);

  { Use corresponding shader when setting uniforms/drawing objects }
  View := FCamera.GetViewMatrix;
  Projection.InitPerspectiveFovRH(Radians(FCamera.Zoom), Width / Height, 0.1, 100.0);

  { Pass matrices to shaders }
  FShaderSingleColor.Use;
  FUniformMVPSingleColor.Apply(View, Projection);

  FShader.Use;
  FUniformMVP.Apply(View, Projection);

  { Draw floor as normal. We only care about the cubes. The floor should NOT
    fill the stencil buffer so we set its mask to $00 }
  glStencilMask($00);

  glBindTexture(GL_TEXTURE_2D, FFloorTexture);
  Model.Init;
  FUniformMVP.Apply(Model);
  FPlaneVAO.Render;

  { Draw 2 cubes
    ============
    1st. Render pass, draw objects as normal, filling the stencil buffer }
  glStencilFunc(GL_ALWAYS, 1, $FF);
  glStencilMask($FF);

  FCubeVAO.BeginRender;

  glBindTexture(GL_TEXTURE_2D, FCubeTexture);
  Model.InitTranslation(-1.0, 0.0, -1.0);
  FUniformMVP.Apply(Model);
  FCubeVAO.Render;

  Model.InitTranslation(2.0, 0.0, 0.0);
  FUniformMVP.Apply(Model);
  FCubeVAO.Render;

  FCubeVAO.EndRender;

  { Draw 2 cubes
    ============
    2nd. Render pass, now draw slightly scaled versions of the objects, this
    time disabling stencil writing.
    Because stencil buffer is now filled with several 1s. The parts of the
    buffer that are 1 are now not drawn, thus only drawing the objects' size
    differences, making it look like borders. }
  glStencilFunc(GL_NOTEQUAL, 1, $FF);
  glStencilMask($00);
  glDisable(GL_DEPTH_TEST);
  FShaderSingleColor.Use;

  FCubeVAO.BeginRender;

  Translate.InitTranslation(-1.0, 0.0, -1.0);
  Scale.InitScaling(SCALE_FACTOR);
  Model := Scale * Translate;
  FUniformMVPSingleColor.Apply(Model);
  FCubeVAO.Render;

  Translate.InitTranslation(2.0, 0.0, 0.0);
  Model := Scale * Translate;
  FUniformMVPSingleColor.Apply(Model);
  FCubeVAO.Render;

  FCubeVAO.EndRender;

  glStencilMask($FF);
  glEnable(GL_DEPTH_TEST);
end;

end.
